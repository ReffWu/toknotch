import XCTest
@testable import Codenotch

/// Pinned to a response recorded from the live endpoint. `/rest/rate-limit/all`
/// is undocumented, so this is the test that fails first if it changes.
final class PerplexityUsageTests: XCTestCase {
    /// Verbatim from the endpoint, with the `sources` connector tail removed.
    private let recorded = """
    {"free_queries":{"available":true,"remaining_detail":{"kind":"exact","remaining":10}},
     "model_specific_limits":{},
     "remaining_agentic_research":0,
     "remaining_labs":0,
     "remaining_pro":2,
     "remaining_research":0}
    """

    private func windows(_ json: String) throws -> [LimitWindow] {
        try PerplexityUsage.windows(fromJSON: json)
    }

    func testReadsTheRecordedResponse() throws {
        let w = try windows(recorded)
        XCTAssertEqual(w.map(\.id),
                       ["remaining_pro", "remaining_research",
                        "remaining_agentic_research", "remaining_labs", "free_queries"])
        XCTAssertEqual(w[0].label, "Pro searches")
        XCTAssertEqual(w[0].remaining, 2)
        XCTAssertEqual(w.last?.remaining, 10)
    }

    /// The endpoint never states a total, so there is nothing to take a
    /// percentage of. Deriving one would mean inventing the denominator.
    func testNoPercentageIsInvented() throws {
        for window in try windows(recorded) {
            XCTAssertNil(window.usedFraction, "\(window.id) grew a percentage from nowhere")
            XCTAssertNil(window.resetsAt, "\(window.id) grew a reset time from nowhere")
        }
    }

    func testSummaryReadsAsACount() throws {
        let w = try windows(recorded)
        XCTAssertEqual(w[0].summary, "2 left")
        XCTAssertEqual(w[1].summary, "0 left")
    }

    func testSingularReadsCorrectly() throws {
        let w = try windows(#"{"remaining_pro": 1}"#)
        XCTAssertEqual(w[0].summary, "1 left")
    }

    /// Pro searches lead, because that is the quota people run out of.
    func testProSearchesAreTheHeadline() throws {
        XCTAssertEqual(try windows(recorded).first?.label, "Pro searches")
    }

    /// Perplexity also reports vaguer kinds; a count we cannot trust is skipped
    /// rather than shown as a number.
    func testSkipsInexactFreeQueryCounts() throws {
        let json = #"{"remaining_pro": 3, "free_queries": {"remaining_detail": {"kind": "approximate", "remaining": 5}}}"#
        XCTAssertEqual(try windows(json).map(\.id), ["remaining_pro"])
    }

    func testRejectsAPayloadWithNoCounters() {
        XCTAssertThrowsError(try windows(#"{"model_specific_limits": {}}"#))
        XCTAssertThrowsError(try windows("not json"))
    }
}
