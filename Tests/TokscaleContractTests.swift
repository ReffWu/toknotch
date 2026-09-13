import XCTest
@testable import TokNotch

/// The bundled tokscale, run for real against session logs whose token counts
/// are known, and decoded by the same code the app reads it with.
///
/// This is what makes moving to a new tokscale safe: if a release changes the
/// JSON TokNotch reads, or starts counting a field differently, this fails
/// before anyone ships it. The fixtures follow the formats Claude Code and
/// Codex actually write.
final class TokscaleContractTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokscaleContract-\(UUID().uuidString)")
        let day = Self.yesterday()

        let claude = home.appendingPathComponent(".claude/projects/-tmp-demo")
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
        try """
        {"type":"assistant","timestamp":"\(day)T10:00:00.000Z","sessionId":"s1","requestId":"req_1","uuid":"u1","message":{"id":"msg_1","type":"message","role":"assistant","model":"claude-sonnet-5","usage":{"input_tokens":100,"output_tokens":50,"cache_read_input_tokens":1000,"cache_creation_input_tokens":200}}}
        {"type":"assistant","timestamp":"\(day)T10:05:00.000Z","sessionId":"s1","requestId":"req_2","uuid":"u2","message":{"id":"msg_2","type":"message","role":"assistant","model":"claude-sonnet-5","usage":{"input_tokens":10,"output_tokens":5,"cache_read_input_tokens":2000,"cache_creation_input_tokens":0}}}

        """.write(to: claude.appendingPathComponent("s1.jsonl"), atomically: true, encoding: .utf8)

        let parts = day.split(separator: "-")
        let codex = home.appendingPathComponent(".codex/sessions/\(parts[0])/\(parts[1])/\(parts[2])")
        try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)
        let usage = #"{"input_tokens":3000,"cached_input_tokens":2000,"output_tokens":400,"reasoning_output_tokens":100,"total_tokens":3400}"#
        try """
        {"timestamp":"\(day)T10:00:00.000Z","type":"session_meta","payload":{"id":"abc","timestamp":"\(day)T10:00:00.000Z","cwd":"/tmp","originator":"codex_cli_rs","cli_version":"0.50.0","model_provider":"openai"}}
        {"timestamp":"\(day)T10:00:01.000Z","type":"turn_context","payload":{"model":"gpt-5.6-terra","cwd":"/tmp"}}
        {"timestamp":"\(day)T10:00:02.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":\(usage),"last_token_usage":\(usage)}}}

        """.write(to: codex.appendingPathComponent("rollout-\(day)T10-00-00-abc.jsonl"),
                  atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    private static func yesterday() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date().addingTimeInterval(-86_400))
    }

    func testTheBundledBinaryIsTheOneThisBuildPinned() throws {
        XCTAssertNotNil(TokscaleCLI.bundledExecutable, "tokscale is not inside the app")
    }

    func testEachToolIsCountedExactly() async throws {
        let report = try await TokscaleCLI.lifetime(home: home.path)
        func totals(_ model: String) -> TokenCounts? {
            report.entries.first { $0.model == model }?.tokens
        }
        // Claude Code: both messages, every field as written.
        XCTAssertEqual(totals("claude-sonnet-5"),
                       TokenCounts(input: 110, output: 55, cacheRead: 3000, cacheWrite: 200))
        // Codex reports cached input inside input and reasoning inside output;
        // tokscale separates both, and TokNotch has to add reasoning back.
        XCTAssertEqual(totals("gpt-5.6-terra"),
                       TokenCounts(input: 1000, output: 300, cacheRead: 2000, reasoning: 100))
    }

    func testTheDailyGraphAgreesWithTheLifetimeTotal() async throws {
        async let graph = TokscaleCLI.graph(home: home.path)
        async let lifetime = TokscaleCLI.lifetime(home: home.path)
        let digest = UsageDigest.build(graph: try await graph, lifetime: try await lifetime)
        XCTAssertEqual(digest.lifetime.totals.tokens, 3365 + 3400)
        XCTAssertEqual(Set(digest.vendors.map(\.vendor)), [.anthropic, .openai])
    }
}
