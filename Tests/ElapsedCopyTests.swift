import XCTest
@testable import Codenotch

final class ElapsedCopyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_787_900_000)

    func testFreshChangesReadAsJustNow() {
        XCTAssertEqual(ElapsedCopy.text(since: now.addingTimeInterval(-5), now: now), "just now")
        XCTAssertEqual(ElapsedCopy.text(since: now.addingTimeInterval(-44), now: now), "just now")
    }

    func testMinutes() {
        XCTAssertEqual(ElapsedCopy.text(since: now.addingTimeInterval(-6 * 60), now: now), "6 min")
        XCTAssertEqual(ElapsedCopy.text(since: now.addingTimeInterval(-59 * 60), now: now), "59 min")
    }

    func testHours() {
        XCTAssertEqual(ElapsedCopy.text(since: now.addingTimeInterval(-60 * 60), now: now), "1 hr")
        XCTAssertEqual(ElapsedCopy.text(since: now.addingTimeInterval(-65 * 60), now: now), "1 hr 5 min")
    }

    /// A clock that has drifted backwards must not print a negative age.
    func testFutureTimestampsDoNotGoNegative() {
        XCTAssertEqual(ElapsedCopy.text(since: now.addingTimeInterval(120), now: now), "just now")
    }
}
