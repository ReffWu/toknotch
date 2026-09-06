import XCTest
@testable import Codenotch

final class UsageBandTests: XCTestCase {
    func testBandsMatchTheDesignFrame() {
        // The three levels the mockup renders, and the colour it renders them in.
        XCTAssertEqual(UsageBand.band(for: 0.21), .ample)
        XCTAssertEqual(UsageBand.band(for: 0.52), .watch)
        XCTAssertEqual(UsageBand.band(for: 0.73), .critical)
    }

    func testBoundaries() {
        XCTAssertEqual(UsageBand.band(for: 0.0), .ample)
        XCTAssertEqual(UsageBand.band(for: 0.4999), .ample)
        XCTAssertEqual(UsageBand.band(for: 0.50), .watch)
        XCTAssertEqual(UsageBand.band(for: 0.6999), .watch)
        XCTAssertEqual(UsageBand.band(for: 0.70), .critical)
        XCTAssertEqual(UsageBand.band(for: 0.9999), .critical)
        XCTAssertEqual(UsageBand.band(for: 1.0), .exhausted)
        XCTAssertEqual(UsageBand.band(for: 1.4), .exhausted)
    }
}
