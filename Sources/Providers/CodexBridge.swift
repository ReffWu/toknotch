import AppKit
import Foundation
import os

/// Asks Codex itself what the account's limits are, instead of reading what it
/// happened to write down last time it ran.
///
/// **Why this exists.** Codex publishes no usage endpoint, so the reading used
/// to come from the `rate_limits` snapshot it records in a thread's rollout
/// log. That is a *file*: it is written during a turn and never again, so the
/// figure is only as fresh as the last time Codex was used. Three days without
/// running it and the notch confidently reported a three-day-old percentage
/// while Codex's own panel, which fetches live, showed a different one.
///
/// Codex ships an app server — the same process its desktop app drives — and it
/// answers `account/rateLimits/read` with the current figure. So this spawns
/// one, asks, and stops it again. Sub-second in practice.
///
/// It is the same bargain as everywhere else here: the number comes from the
/// vendor's own tool, so the vendor's own tool has to be installed. Where it is
/// not, the rollout is still there to fall back on.
enum CodexBridge {
    /// The desktop app that carries the `codex` binary. Named `com.openai.codex`
    /// even though the bundle on disk is ChatGPT.app.
    static let appBundleID = "com.openai.codex"

    /// Where to look for the binary, in order.
    ///
    /// The app bundle first: it is the copy that matches the app writing the
    /// rollouts. A standalone CLI install is the fallback.
    static func candidatePaths(home: String = NSHomeDirectory(),
                               appBundle: URL? = nil) -> [URL] {
        var paths: [URL] = []
        if let appBundle {
            paths.append(appBundle.appendingPathComponent("Contents/Resources/codex"))
        }
        paths.append(URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex"))
        paths.append(URL(fileURLWithPath: home).appendingPathComponent(".codex/bin/codex"))
        paths.append(URL(fileURLWithPath: "/opt/homebrew/bin/codex"))
        paths.append(URL(fileURLWithPath: "/usr/local/bin/codex"))
        return paths
    }

    static func executable(fileManager: FileManager = .default) -> URL? {
        let bundle = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appBundleID)
        let found = candidatePaths(appBundle: bundle).first {
            fileManager.isExecutableFile(atPath: $0.path)
        }
        if found == nil {
            Log.usage.notice("codex: no app server binary found — falling back to the rollout")
        }
        return found
    }

    // MARK: - Asking

    /// One request/response against a freshly spawned app server.
    ///
    /// All three messages go out at once rather than waiting for the handshake
    /// to answer: the server reads them in order, and a round trip saved here is
    /// a round trip saved on every poll.
    static func rateLimits(executable: URL, timeout: TimeInterval = 10) throws -> Data {
        let process = Process()
        process.executableURL = executable
        process.arguments = ["app-server"]
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()

        // A watchdog, because a server that never answers would otherwise hold
        // the pipe open for ever. Terminating it closes the pipe, which is what
        // ends the read loop below.
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        defer {
            watchdog.cancel()
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
        }

        Log.usage.debug("codex: asking \(executable.path, privacy: .public) for rate limits")
        for line in handshake { input.fileHandleForWriting.write(Data((line + "\n").utf8)) }

        var buffer = Data()
        while true {
            let chunk = output.fileHandleForReading.availableData
            if chunk.isEmpty { break }        // the server exited or was stopped
            buffer.append(chunk)
            if let answer = response(id: requestID, inLines: buffer) { return answer }
        }
        // Whatever it did say, so a protocol change is visible rather than
        // silently becoming a stale rollout reading.
        Log.usage.error("codex: app server gave no answer to id \(requestID); said: \(String(decoding: buffer.prefix(400), as: UTF8.self), privacy: .public)")
        throw UsageProviderError.nothingMetered("Codex's app server did not answer")
    }

    static let requestID = 2

    static var handshake: [String] {
        let version = Bundle.main
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return [
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":"#
                + #"{"name":"codenotch","title":"Codenotch","version":"\#(version)"}}}"#,
            #"{"jsonrpc":"2.0","method":"initialized","params":{}}"#,
            #"{"jsonrpc":"2.0","id":\#(requestID),"method":"account/rateLimits/read","params":null}"#
        ]
    }

    /// The server interleaves notifications with replies, so the reply has to be
    /// picked out by id rather than taken as "the next line".
    static func response(id: Int, inLines buffer: Data) -> Data? {
        for line in buffer.split(separator: UInt8(ascii: "\n")) {
            let data = Data(line)
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (object["id"] as? NSNumber)?.intValue == id,
                  object["result"] != nil
            else { continue }
            return data
        }
        return nil
    }

    // MARK: - Reading the answer

    /// Turns the reply into limit windows.
    ///
    /// The same two windows the rollout carries and under the same ids, so the
    /// headline still means the same thing whichever source answered — only the
    /// spelling differs: `usedPercent` here against `used_percent` there.
    static func windows(in data: Data, now: Date = Date()) -> [LimitWindow] {
        struct Reply: Decodable {
            struct Window: Decodable {
                let usedPercent: Double?
                let windowDurationMins: Double?
                let resetsAt: Double?
            }
            struct Limits: Decodable {
                let primary: Window?
                let secondary: Window?
                let planType: String?
            }
            struct Result: Decodable { let rateLimits: Limits? }
            let result: Result?
        }

        guard let reply = try? JSONDecoder().decode(Reply.self, from: data),
              let limits = reply.result?.rateLimits
        else { return [] }

        return [(limits.primary, "primary"), (limits.secondary, "secondary")]
            .compactMap { window, id in
                guard let window, let percent = window.usedPercent else { return nil }
                return LimitWindow(
                    id: id,
                    label: CodexUsage.label(windowMinutes: window.windowDurationMins,
                                            fallback: id),
                    usedFraction: percent / 100,
                    resetsAt: window.resetsAt.map { Date(timeIntervalSince1970: $0) }
                )
            }
    }

    /// Whether the account is blocked right now, and why.
    ///
    /// `rateLimitReachedType` is null in the ordinary case. When it is not, the
    /// account has hit something — its own allowance, or a workspace's — and
    /// the headline percentage is no longer the whole story.
    static func block(in data: Data) -> UsageBlock? {
        struct Reply: Decodable {
            struct Window: Decodable { let resetsAt: Double? }
            struct Limits: Decodable {
                let primary: Window?
                let secondary: Window?
                let rateLimitReachedType: String?
            }
            struct Result: Decodable { let rateLimits: Limits? }
            let result: Result?
        }
        guard let limits = try? JSONDecoder().decode(Reply.self, from: data).result?.rateLimits,
              let reached = limits.rateLimitReachedType
        else { return nil }

        let resets = limits.primary?.resetsAt ?? limits.secondary?.resetsAt
        return UsageBlock(reason: reason(forReachedType: reached),
                          resetsAt: resets.map { Date(timeIntervalSince1970: $0) })
    }

    /// Codex's own vocabulary, turned into something worth reading on a notch.
    static func reason(forReachedType type: String) -> String {
        switch type {
        case "rate_limit_reached":
            return "Paused"
        case "workspace_owner_credits_depleted", "workspace_member_credits_depleted":
            return "Workspace credits used up"
        case "workspace_owner_usage_limit_reached", "workspace_member_usage_limit_reached":
            return "Workspace limit reached"
        default:
            // An unknown value still means blocked; saying so beats saying
            // nothing because the spelling changed.
            return "Paused"
        }
    }

    /// The plan, as Codex names it — better than the one in the id token, which
    /// goes stale when a plan changes.
    static func planType(in data: Data) -> String? {
        struct Reply: Decodable {
            struct Limits: Decodable { let planType: String? }
            struct Result: Decodable { let rateLimits: Limits? }
            let result: Result?
        }
        return try? JSONDecoder().decode(Reply.self, from: data).result?.rateLimits?.planType
    }
}
