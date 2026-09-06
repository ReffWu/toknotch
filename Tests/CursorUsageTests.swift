import XCTest
@testable import Codenotch

/// Pinned to a response recorded from a live free account. `/api/usage-summary`
/// is not a documented API, so this is what fails first if it changes.
final class CursorUsageTests: XCTestCase {
    /// Verbatim, from the account the editor is signed into.
    private let recorded = """
    {"billingCycleStart":"2026-08-24T03:32:15.933Z",
     "billingCycleEnd":"2026-09-24T03:32:15.933Z",
     "membershipType":"free","limitType":"user","isUnlimited":false,
     "autoModelSelectedDisplayMessage":"You've used 10% of your included total usage",
     "namedModelSelectedDisplayMessage":"You've used 19% of your included API usage",
     "individualUsage":{
       "plan":{"enabled":true,"used":0,"limit":0,"remaining":0,
               "breakdown":{"included":0,"bonus":19,"total":19},
               "autoPercentUsed":0,"apiPercentUsed":19,"totalPercentUsed":9.5},
       "onDemand":{"enabled":false,"used":0,"limit":null,"remaining":null}},
     "teamUsage":{}}
    """

    private func windows(_ json: String) throws -> [LimitWindow] {
        try CursorUsage.windows(fromJSON: json)
    }

    /// The bug this replaced: `used`/`limit` are both zero on a free plan even
    /// while real usage is happening, because the allowance arrives as
    /// `breakdown.bonus`. Reading them reported 0% for an account 10% through
    /// its month. `totalPercentUsed` is what the dashboard actually shows.
    func testReadsThePercentageTheDashboardShows() throws {
        let w = try windows(recorded)
        XCTAssertEqual(w[0].id, "included")
        XCTAssertEqual(w[0].label, "Included usage")
        XCTAssertEqual(w[0].usedFraction ?? -1, 0.095, accuracy: 0.0001)
        XCTAssertEqual(w[0].summary, "10% Used · 90% left",
                       "should round the way Cursor does, and show both ends")
    }

    func testApiUsageIsReportedSeparately() throws {
        let w = try windows(recorded)
        XCTAssertEqual(w.map(\.id), ["included", "api"])
        XCTAssertEqual(w[1].usedFraction ?? -1, 0.19, accuracy: 0.0001)
    }

    /// It is only worth a row when it has actually been touched.
    func testZeroApiUsageIsOmitted() throws {
        let json = """
        {"individualUsage":{"plan":{"totalPercentUsed":4,"apiPercentUsed":0}}}
        """
        XCTAssertEqual(try windows(json).map(\.id), ["included"])
    }

    /// The reset is Cursor's own `billingCycleEnd` — Sep 24 here, which is what
    /// the dashboard prints, and is *not* a month after `billingCycleStart`.
    func testResetComesFromTheBillingCycleEnd() throws {
        let reset = try XCTUnwrap(windows(recorded)[0].resetsAt)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(calendar.component(.month, from: reset), 9)
        XCTAssertEqual(calendar.component(.day, from: reset), 24)
    }

    func testOnDemandOnlyCountsWhenSwitchedOnWithACeiling() throws {
        let on = """
        {"individualUsage":{"plan":{"totalPercentUsed":5},
                            "onDemand":{"enabled":true,"used":3,"limit":50}}}
        """
        XCTAssertEqual(try windows(on).map(\.id), ["included", "on_demand"])

        let off = """
        {"individualUsage":{"plan":{"totalPercentUsed":5},
                            "onDemand":{"enabled":false,"used":0,"limit":null}}}
        """
        XCTAssertEqual(try windows(off).map(\.id), ["included"])
    }

    func testNothingMeteredRatherThanAFalseZero() {
        let json = #"{"membershipType":"free","individualUsage":{"plan":{}}}"#
        XCTAssertThrowsError(try windows(json)) { error in
            guard case UsageProviderError.nothingMetered = error else {
                return XCTFail("expected nothingMetered, got \(error)")
            }
        }
    }

    func testRejectsRubbish() {
        XCTAssertThrowsError(try windows("not json"))
    }
}

/// Borrowing the editor's session is what stops the notch reporting a different
/// account's usage — signing into cursor.com separately made a second, empty one.
final class CursorCredentialsTests: XCTestCase {
    func testCookieIsTheAccountAndTokenPair() {
        let credentials = CursorCredentials(accountID: "google-oauth2|user_ABC", accessToken: "tok")
        XCTAssertEqual(credentials.sessionCookie, "WorkosCursorSessionToken=google-oauth2|user_ABC::tok")
    }

    func testAMissingStoreMeansSignedOutRatherThanAnError() {
        let missing = URL(fileURLWithPath: "/tmp/definitely-not-here-\(UUID().uuidString).vscdb")
        XCTAssertThrowsError(try CursorCredentials.load(from: missing)) { error in
            guard case UsageProviderError.needsAuth = error else {
                return XCTFail("expected needsAuth, got \(error)")
            }
        }
    }
}

/// Confirmed against a real account switched mid-cycle: Cursor reports 0% and
/// means it. An earlier version suppressed this as "no allowance to be a
/// percentage of", which hid a correct reading — Cursor's own response says
/// "You've used 0% of your included total usage" in the same payload.
final class CursorZeroUsageTests: XCTestCase {
    /// Verbatim from a live free account, just after signing into a new one.
    private let freePlan = """
    {"billingCycleEnd":"2026-09-20T01:35:15.142Z","membershipType":"free","isUnlimited":false,
     "autoModelSelectedDisplayMessage":"You've used 0% of your included total usage",
     "individualUsage":{"plan":{"enabled":true,"used":0,"limit":0,"remaining":0,
       "breakdown":{"included":0,"bonus":0,"total":0},
       "autoPercentUsed":0,"apiPercentUsed":0,"totalPercentUsed":0},
      "onDemand":{"enabled":false,"used":0,"limit":null,"remaining":null}}}
    """

    func testZeroPercentIsShownRatherThanSuppressed() throws {
        let windows = try CursorUsage.windows(fromJSON: freePlan)
        XCTAssertEqual(windows.first?.id, "included")
        XCTAssertEqual(windows.first?.usedFraction, 0)
    }

    func testItStillReadsARealPercentage() throws {
        let used = freePlan.replacingOccurrences(of: "\"totalPercentUsed\":0",
                                                 with: "\"totalPercentUsed\":34")
        let windows = try CursorUsage.windows(fromJSON: used)
        XCTAssertEqual(windows.first?.usedFraction ?? 0, 0.34, accuracy: 0.0001)
    }
}
