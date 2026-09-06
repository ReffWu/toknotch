import Foundation
import os

/// Asks Antigravity's own language server for the quota, instead of asking
/// Google directly.
///
/// Google refuses us: `retrieveUserQuotaSummary` on `cloudcode-pa` answers 403
/// "You do not have a valid license of this product" for a personal account,
/// because the API judges *which client* is asking and Codenotch cannot
/// honestly claim to be Antigravity. Antigravity's window has the same problem
/// and solves it the same way — it never calls Google for this either. It calls
/// the language server running on this machine, which already holds the
/// credential and the client identity, and lets that make the call.
///
/// So this is not a workaround for a locked door; it is the door Antigravity
/// itself uses. It works only while Antigravity is running, which is honest:
/// the figure comes from Antigravity, so Antigravity has to be there.
enum AntigravityBridge {
    /// Where the language server is listening, and the token it demands.
    struct Endpoint: Equatable {
        /// Every port the server listens on. It opens two and only one serves
        /// this RPC, and which is which is not advertised — so both are tried
        /// rather than guessed at.
        let ports: [Int]
        let csrfToken: String
    }

    /// Antigravity is built on Codeium's stack, and the header still says so.
    /// Six plausible spellings were rejected before this one was found in the
    /// binary — the server's only complaint is "missing CSRF token", never
    /// which header it wanted.
    static let csrfHeader = "x-codeium-csrf-token"

    private static let service =
        "/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary"

    // MARK: - Finding it

    /// The token is passed to the language server on its command line, so the
    /// process table is the source of truth. There is no file to read: the
    /// server is started with `--https_server_port 0`, meaning the port is
    /// chosen at runtime and never written down.
    static func discover(processTable: String? = nil, listeningPorts: ((Int) -> [Int])? = nil)
        -> Endpoint? {
        let table = processTable ?? run("/bin/ps", ["-Ao", "pid,command"])
        guard let line = table.split(separator: "\n").first(where: {
            $0.contains("language_server") && $0.contains("--csrf_token")
        }) else { return nil }

        guard let token = value(of: "--csrf_token", in: String(line)),
              let pid = Int(line.trimmingCharacters(in: .whitespaces)
                  .split(separator: " ").first ?? "")
        else { return nil }

        let ports = listeningPorts?(pid) ?? self.listeningPorts(ofPID: pid)
        guard !ports.isEmpty else { return nil }
        return Endpoint(ports: ports, csrfToken: token)
    }

    static func value(of flag: String, in line: String) -> String? {
        let parts = line.split(separator: " ")
        guard let index = parts.firstIndex(of: Substring(flag)),
              index + 1 < parts.count else { return nil }
        return String(parts[index + 1])
    }

    /// Ports are found rather than assumed. The server opens two and only one
    /// serves this RPC, so every candidate is tried in turn.
    static func listeningPorts(ofPID pid: Int) -> [Int] {
        // `-a` is load-bearing: without it lsof ORs the filters rather than
        // ANDing them, and returns every listening socket on the machine. The
        // first match was another process entirely, so the bridge dialled the
        // wrong port and silently fell back to counting requests.
        let output = run("/usr/sbin/lsof", ["-nP", "-a", "-p", "\(pid)", "-iTCP", "-sTCP:LISTEN"])
        return parsePorts(fromLSOF: output)
    }

    static func parsePorts(fromLSOF output: String) -> [Int] {
        output.split(separator: "\n").compactMap { line in
            guard let address = line.split(separator: " ").last(where: { $0.contains(":") }),
                  let port = Int(address.split(separator: ":").last ?? "") else { return nil }
            return port
        }
    }

    // MARK: - Asking it

    static func quota(from endpoint: Endpoint, session: URLSession) async throws -> [LimitWindow] {
        var lastError: Error?
        for port in endpoint.ports {
            do {
                let windows = try await quota(port: port, token: endpoint.csrfToken,
                                              session: session)
                if !windows.isEmpty { return windows }
            } catch {
                lastError = error
            }
        }
        if let lastError { throw lastError }
        return []
    }

    private static func quota(port: Int, token: String,
                              session: URLSession) async throws -> [LimitWindow] {
        var request = URLRequest(
            url: URL(string: "https://127.0.0.1:\(port)\(service)")!
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: csrfHeader)
        // `forceRefresh` is why this reads as live rather than as whatever was
        // last looked at. The language server keeps a `QuotaSummaryCache`, and
        // an empty request is served from it — so the figure only moved when
        // something else refreshed it, which in practice meant opening
        // Antigravity's own Models & Usage panel and pressing its refresh
        // button. The field is real: `RetrieveUserQuotaSummaryRequest` has a
        // `GetForceRefresh` accessor.
        request.httpBody = Data(#"{"forceRefresh":true}"#.utf8)
        request.timeoutInterval = 10

        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw UsageProviderError.badResponse(
                status: (response as? HTTPURLResponse)?.statusCode ?? 0
            )
        }
        return windows(in: data)
    }

    /// Turns the quota summary into limit windows.
    ///
    /// The server reports what is **left**, not what is spent — the notch shows
    /// the opposite, so every fraction is inverted here rather than in the view,
    /// where it would be a percentage whose meaning depended on the provider.
    static func windows(in data: Data) -> [LimitWindow] {
        struct Response: Decodable {
            struct Bucket: Decodable {
                let bucketId: String?
                let displayName: String?
                let remainingFraction: Double?
                let resetTime: String?
            }
            struct Group: Decodable {
                let displayName: String?
                let buckets: [Bucket]?
            }
            struct Body: Decodable { let groups: [Group]? }
            let response: Body?
        }

        guard let decoded = try? JSONDecoder().decode(Response.self, from: data),
              let groups = decoded.response?.groups
        else { return [] }

        return groups.flatMap { group -> [LimitWindow] in
            (group.buckets ?? []).compactMap { bucket in
                guard let remaining = bucket.remainingFraction,
                      remaining >= 0, remaining <= 1
                else { return nil }
                return LimitWindow(
                    id: bucket.bucketId ?? group.displayName ?? "quota",
                    // The group names the models; the bucket only ever says
                    // "Weekly Limit Remaining", which is the same for both.
                    label: group.displayName ?? bucket.displayName ?? "Usage",
                    usedFraction: 1 - remaining,
                    resetsAt: bucket.resetTime.flatMap(AntigravityCredentials.parse)
                )
            }
        }
    }

    // MARK: - Plumbing

    private static func run(_ path: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
