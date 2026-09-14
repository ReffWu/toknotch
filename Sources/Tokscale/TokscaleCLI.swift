import Foundation

/// The two JSON exits tokscale publishes, and nothing else.
///
/// Deliberately *not* `~/.config/tokscale/cache/tui-data-cache.json`. That file
/// is the TUI's own scratch space: it is rewritten only while the TUI itself is
/// running, so a notch reading from it can be showing hours-old numbers; its
/// `daily` array is capped at a rolling window; and its shape is free to change
/// in any tokscale release. Measured against it, the totals it carries were
/// also simply wrong — 16.06B where all three of tokscale's own published
/// figures agree on 15.43B.
///
/// Both commands here return in well under a second once tokscale's index is
/// warm (the multi-second figure in `processingTimeMs` is the one-off cost of
/// building that index), which is cheap enough to just call on a timer.
enum TokscaleCLI {
    /// The copy inside the app, falling back to one installed on this Mac.
    ///
    /// Bundled first, and deliberately so: it is the version this build was
    /// written against and tested with, it is always there, and it means
    /// installing TokNotch is the whole setup — no Homebrew, no npm, no node
    /// runtime. tokscale's own binary is a self-contained Mach-O that links
    /// nothing outside the system frameworks, which is what makes shipping it
    /// possible at all. It is MIT licensed; see `Vendor/tokscale/LICENSE`.
    ///
    /// The fallbacks stay for the development build, where the app may be run
    /// from a location that has no resources copied yet.
    static var executable: String {
        if let bundled = bundledExecutable { return bundled }
        let installed = ["/opt/homebrew/bin/tokscale", "/usr/local/bin/tokscale"]
        return installed.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "tokscale"
    }

    /// The bundled binary's path, if this build has one that can actually run.
    static var bundledExecutable: String? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let path = resources.appendingPathComponent("tokscale/tokscale").path
        // The executable bit survives Xcode's copy, but a corrupted or
        // half-copied build should fall through to an installed copy rather
        // than fail every read.
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    /// The `PATH` the subprocess gets, which cannot be the one we inherit.
    ///
    /// A GUI app launched from Finder inherits a minimal environment —
    /// `/usr/bin:/bin:/usr/sbin:/sbin` — not the `PATH` a login shell builds
    /// from the user's profile. That is enough to *find* tokscale, whose own
    /// path is absolute, but not to run it: it is a `#!/usr/bin/env node`
    /// script, so `node` has to be findable too, and node lives wherever the
    /// user's version manager put it. Without this every read fails with exit
    /// 127 while the identical command works perfectly in a terminal — which
    /// is the most confusing possible way for this to break.
    static var searchPath: String {
        let home = NSHomeDirectory()
        var directories = [
            "/opt/homebrew/bin", "/usr/local/bin", "/opt/homebrew/opt/node/bin",
            "\(home)/.volta/bin", "\(home)/.bun/bin", "\(home)/.local/bin",
            "\(home)/.npm-global/bin", "/opt/local/bin"
        ]
        // nvm and fnm keep one directory per installed version, so the right
        // one has to be looked up rather than named.
        for manager in ["\(home)/.nvm/versions/node", "\(home)/.local/share/fnm/node-versions"] {
            let versions = (try? FileManager.default.contentsOfDirectory(atPath: manager)) ?? []
            if let newest = versions.sorted().last {
                directories.append("\(manager)/\(newest)/bin")
                directories.append("\(manager)/\(newest)/installation/bin")
            }
        }
        let inherited = ProcessInfo.processInfo.environment["PATH"] ?? ""
        return (directories + [inherited, "/usr/bin", "/bin"])
            .filter { !$0.isEmpty }
            .joined(separator: ":")
    }

    enum Failure: LocalizedError, Equatable {
        case notInstalled
        case exited(code: Int32)
        case undecodable(String)
        case timedOut

        var errorDescription: String? {
            switch self {
            case .notInstalled:      return "tokscale not found"
            case .exited(127):       return "tokscale could not start — node was not found"
            case .exited(let code):  return "tokscale exited \(code)"
            case .undecodable(let w): return "unreadable tokscale output — \(w)"
            case .timedOut:          return "tokscale did not finish in time"
            }
        }
    }

    /// Per-day totals with a model-and-route breakdown inside each day, for the
    /// window tokscale keeps day-level history over (~96 days). Everything the
    /// today and month rings need — including their baselines — comes from this
    /// one call.
    ///
    /// `home` points tokscale at another home directory, which is how the
    /// contract tests feed it session logs with known token counts.
    static func graph(home: String? = nil) async throws -> GraphReport {
        try await run(["graph", "--no-spinner"] + homeArguments(home), as: GraphReport.self)
    }

    /// Every session tokscale can see, grouped by model. The lifetime ring's
    /// source, and the only one that reaches past the day-level window.
    static func lifetime(home: String? = nil) async throws -> UsageReport {
        try await run(["--json", "--no-spinner", "--group-by", "client,provider,model"]
                          + homeArguments(home),
                      as: UsageReport.self)
    }

    /// Antigravity keeps no session log tokscale can scan. Its usage lives in
    /// the language servers the running app starts, and tokscale only reports
    /// it after `antigravity sync` has copied it into tokscale's own cache —
    /// so without this, Antigravity's Gemini usage simply stopped at whenever
    /// that command was last run by hand. Local only: it talks to the language
    /// server on this Mac, not to any account.
    static func syncAntigravity() async throws {
        _ = try await launch(["antigravity", "sync"], timeout: 90)
    }

    private static func homeArguments(_ home: String?) -> [String] {
        home.map { ["--home", $0] } ?? []
    }

    private static func run<T: Decodable>(_ arguments: [String], as: T.Type) async throws -> T {
        let data = try await launch(arguments)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw Failure.undecodable(String(describing: error))
        }
    }

    /// Runs tokscale and returns what it printed.
    ///
    /// With a deadline: a tokscale that hangs (a stuck language server, a
    /// wedged file system) would otherwise hold the refresh forever, and since
    /// only one refresh runs at a time the numbers would silently stop moving.
    private static func launch(_ arguments: [String],
                               timeout: TimeInterval = 120) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                // tokscale finds the agents' session directories under $HOME, and
                // a GUI app does not necessarily inherit a useful one.
                var environment = ProcessInfo.processInfo.environment
                environment["HOME"] = NSHomeDirectory()
                environment["PATH"] = searchPath
                process.environment = environment

                let output = Pipe()
                process.standardOutput = output
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: Failure.notInstalled)
                    return
                }
                var timedOut = false
                let deadline = DispatchWorkItem {
                    if process.isRunning {
                        timedOut = true
                        process.terminate()
                    }
                }
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout,
                                                               execute: deadline)
                // Read before waiting: a report large enough to fill the pipe
                // buffer deadlocks a process that is waited on first.
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                deadline.cancel()

                guard !timedOut else {
                    continuation.resume(throwing: Failure.timedOut)
                    return
                }
                guard process.terminationStatus == 0 else {
                    continuation.resume(throwing: Failure.exited(code: process.terminationStatus))
                    return
                }
                continuation.resume(returning: data)
            }
        }
    }
}

// MARK: - What the two commands return

/// The five counters tokscale reports for any slice of usage.
///
/// `reasoning` is part of the total and is easy to miss — leaving it out is a
/// silent undercount (11M tokens across this machine's history) that makes the
/// app disagree with tokscale's own headline for no visible reason.
struct TokenCounts: Decodable, Equatable {
    var input: Int64 = 0
    var output: Int64 = 0
    var cacheRead: Int64 = 0
    var cacheWrite: Int64 = 0
    var reasoning: Int64 = 0

    var total: Int64 { input + output + cacheRead + cacheWrite + reasoning }

    enum CodingKeys: String, CodingKey {
        case input, output, cacheRead, cacheWrite, reasoning
    }

    init(input: Int64 = 0, output: Int64 = 0, cacheRead: Int64 = 0,
         cacheWrite: Int64 = 0, reasoning: Int64 = 0) {
        self.input = input; self.output = output; self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite; self.reasoning = reasoning
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        input      = try c.decodeIfPresent(Int64.self, forKey: .input) ?? 0
        output     = try c.decodeIfPresent(Int64.self, forKey: .output) ?? 0
        cacheRead  = try c.decodeIfPresent(Int64.self, forKey: .cacheRead) ?? 0
        cacheWrite = try c.decodeIfPresent(Int64.self, forKey: .cacheWrite) ?? 0
        reasoning  = try c.decodeIfPresent(Int64.self, forKey: .reasoning) ?? 0
    }

    static func + (a: TokenCounts, b: TokenCounts) -> TokenCounts {
        TokenCounts(input: a.input + b.input,
                    output: a.output + b.output,
                    cacheRead: a.cacheRead + b.cacheRead,
                    cacheWrite: a.cacheWrite + b.cacheWrite,
                    reasoning: a.reasoning + b.reasoning)
    }
}

/// `tokscale graph` — one entry per day, each carrying its own model breakdown.
struct GraphReport: Decodable, Equatable {
    struct Day: Decodable, Equatable {
        /// `yyyy-MM-dd`, in the machine's own time zone.
        let date: String
        let tokenBreakdown: TokenCounts
        let clients: [Line]
        let cost: Double
        let messages: Int

        /// One model, as reached through one route, on that day.
        struct Line: Decodable, Equatable {
            let modelId: String
            let tokens: TokenCounts
            let cost: Double
            let messages: Int

            enum CodingKeys: String, CodingKey { case modelId, tokens, cost, messages }

            init(modelId: String, tokens: TokenCounts, cost: Double, messages: Int) {
                self.modelId = modelId; self.tokens = tokens
                self.cost = cost; self.messages = messages
            }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                modelId  = try c.decodeIfPresent(String.self, forKey: .modelId) ?? "unknown"
                tokens   = try c.decodeIfPresent(TokenCounts.self, forKey: .tokens) ?? TokenCounts()
                cost     = try c.decodeIfPresent(Double.self, forKey: .cost) ?? 0
                messages = try c.decodeIfPresent(Int.self, forKey: .messages) ?? 0
            }
        }

        enum CodingKeys: String, CodingKey { case date, tokenBreakdown, clients, totals }
        private struct Totals: Decodable { let cost: Double?; let messages: Int? }

        init(date: String, tokenBreakdown: TokenCounts, clients: [Line],
             cost: Double, messages: Int) {
            self.date = date; self.tokenBreakdown = tokenBreakdown
            self.clients = clients; self.cost = cost; self.messages = messages
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            date           = try c.decodeIfPresent(String.self, forKey: .date) ?? ""
            tokenBreakdown = try c.decodeIfPresent(TokenCounts.self, forKey: .tokenBreakdown) ?? TokenCounts()
            clients        = try c.decodeIfPresent([Line].self, forKey: .clients) ?? []
            let totals     = try c.decodeIfPresent(Totals.self, forKey: .totals)
            cost           = totals?.cost ?? 0
            messages       = totals?.messages ?? 0
        }
    }

    let contributions: [Day]

    enum CodingKeys: String, CodingKey { case contributions }

    init(contributions: [Day]) { self.contributions = contributions }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        contributions = try c.decodeIfPresent([Day].self, forKey: .contributions) ?? []
    }
}

/// `tokscale --json` — no day dimension, but it reaches all the way back.
struct UsageReport: Decodable, Equatable {
    struct Entry: Decodable, Equatable {
        let model: String
        let tokens: TokenCounts
        let cost: Double
        let messages: Int

        enum CodingKeys: String, CodingKey {
            case model, cost, messageCount, input, output, cacheRead, cacheWrite, reasoning
        }

        init(model: String, tokens: TokenCounts, cost: Double, messages: Int) {
            self.model = model; self.tokens = tokens
            self.cost = cost; self.messages = messages
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            model    = try c.decodeIfPresent(String.self, forKey: .model) ?? "unknown"
            cost     = try c.decodeIfPresent(Double.self, forKey: .cost) ?? 0
            messages = try c.decodeIfPresent(Int.self, forKey: .messageCount) ?? 0
            // Flat here, nested under `tokens` in the graph report.
            tokens = TokenCounts(
                input:      try c.decodeIfPresent(Int64.self, forKey: .input) ?? 0,
                output:     try c.decodeIfPresent(Int64.self, forKey: .output) ?? 0,
                cacheRead:  try c.decodeIfPresent(Int64.self, forKey: .cacheRead) ?? 0,
                cacheWrite: try c.decodeIfPresent(Int64.self, forKey: .cacheWrite) ?? 0,
                reasoning:  try c.decodeIfPresent(Int64.self, forKey: .reasoning) ?? 0
            )
        }
    }

    let entries: [Entry]
    let messages: Int

    enum CodingKeys: String, CodingKey { case entries, totalMessages }

    init(entries: [Entry], messages: Int) { self.entries = entries; self.messages = messages }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        entries  = try c.decodeIfPresent([Entry].self, forKey: .entries) ?? []
        messages = try c.decodeIfPresent(Int.self, forKey: .totalMessages) ?? 0
    }
}
