import XCTest
@testable import TokNotch

/// End-to-end against the real tokscale on this machine.
///
/// Skipped unless `TOKSCALE_PROBE=1`, because it shells out and depends on
/// whatever this Mac has actually run — but when it does run it is the only
/// check that the published JSON, the decoders, the aggregation and the wording
/// all still line up with the tool as installed.
final class RealDataProbeTests: XCTestCase {
    func testTheWholeChainAgainstTheRealTool() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["TOKSCALE_PROBE"] == "1")

        let graph = try await TokscaleCLI.graph()
        let lifetime = try await TokscaleCLI.lifetime()
        XCTAssertFalse(graph.contributions.isEmpty, "graph returned no days")
        XCTAssertFalse(lifetime.entries.isEmpty, "no lifetime entries")

        let digest = UsageDigest.build(graph: graph, lifetime: lifetime)
        let rings = RingBuilder.rings(from: digest, vendors: Set(digest.vendors.map(\.vendor)),
                                      language: .simplifiedChinese)

        print("\n════════ 真实数据 ════════")
        for ring in rings {
            print("\n◆ \(ring.title) · \(ring.caption)   [环下 \(ring.headline)]")
            print("  ▸ \(ring.hero)   \(ring.heroCaption)")
            for row in ring.rows {
                let bar = row.fraction.map { String(format: "  (%.0f%%)", $0 * 100) } ?? ""
                print("    \(row.label)  ·  \(row.value)\(bar)")
            }
        }
        print("\n可选服务商: \(digest.vendors.map { "\($0.vendor.title(.simplifiedChinese))" }.joined(separator: ", "))")
        print("════════════════════════\n")

        // The lifetime total must match tokscale's own arithmetic exactly.
        let expected = lifetime.entries.reduce(Int64(0)) { $0 + $1.tokens.total }
        XCTAssertEqual(digest.lifetime.totals.tokens, expected)
    }
}
