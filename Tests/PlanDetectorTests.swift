import XCTest
@testable import TokNotch

/// Reading a plan out of a tool's own configuration.
final class PlanDetectorTests: XCTestCase {
    private func write(_ json: String) throws -> String {
        let path = NSTemporaryDirectory() + "claude-\(UUID().uuidString).json"
        try json.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    func testItReadsThePlanAndTheRenewalDay() throws {
        let path = try write("""
        {"oauthAccount": {
            "organizationType": "claude_pro",
            "billingType": "stripe_subscription",
            "subscriptionCreatedAt": "2023-10-03T23:13:02.277543Z"
        }}
        """)
        let plan = try XCTUnwrap(PlanDetector.detectClaude(path: path))
        XCTAssertEqual(plan.planID, "claude_pro")
        XCTAssertEqual(plan.name, "Claude Pro")
        XCTAssertEqual(plan.monthlyUSD, 20)
        XCTAssertEqual(plan.renewalDay, 3, "the renewal day is the day billing started")
        XCTAssertEqual(plan.subscription?.monthlyUSD, 20)
    }

    /// An account billed some other way has no monthly figure to compare
    /// against, and inventing one would be worse than saying nothing.
    func testAnAccountBilledAnotherWayIsNotAPlan() throws {
        let path = try write("""
        {"oauthAccount": {"organizationType": "claude_pro", "billingType": "api_credit"}}
        """)
        XCTAssertNil(PlanDetector.detectClaude(path: path))
    }

    /// A plan id we have no price for still identifies itself; it just cannot
    /// fill in an amount.
    func testAnUnknownPlanIsNamedButNotPriced() throws {
        let path = try write("""
        {"oauthAccount": {"organizationType": "claude_future_tier",
                          "billingType": "stripe_subscription"}}
        """)
        let plan = try XCTUnwrap(PlanDetector.detectClaude(path: path))
        XCTAssertEqual(plan.name, "Claude Future Tier")
        XCTAssertNil(plan.monthlyUSD)
        XCTAssertNil(plan.subscription, "an unpriced plan cannot produce a payback figure")
    }

    func testAConfigWithNoAccountIsNotAPlan() throws {
        XCTAssertNil(PlanDetector.detectClaude(path: try write("{}")))
        XCTAssertNil(PlanDetector.detectClaude(path: "/nowhere/at/all.json"))
    }

    /// Every price in the catalogue has to be reachable by the id a vendor
    /// actually reports, or detection silently falls through to "unknown".
    func testTheCatalogueIsLookupableByID() {
        for vendor in Vendor.allCases {
            for plan in PlanCatalog.plans(for: vendor) {
                XCTAssertEqual(PlanCatalog.plan(id: plan.id, for: vendor), plan)
            }
        }
        XCTAssertEqual(PlanCatalog.plan(id: "claude_pro", for: .anthropic)?.monthlyUSD, 20)
    }
}

/// The range a payback bar is drawn against.
final class PaybackScaleTests: XCTestCase {
    /// Below break-even the bar is simply a fraction of 1×, and there is no
    /// tick — it would sit on the end of the bar and say nothing.
    func testBelowBreakEvenTheBarIsPlain() {
        let scale = PaybackScale.around(0.6)
        XCTAssertEqual(scale.ceiling, 1)
        XCTAssertNil(scale.breakEven)
        XCTAssertEqual(scale.fill(0.6), 0.6, accuracy: 0.0001)
    }

    /// Past break-even the range steps up, so the bar keeps saying how far past
    /// it you are instead of just being full.
    func testTheRangeClimbsWithTheMultiple() {
        XCTAssertEqual(PaybackScale.around(1.3).ceiling, 2)
        XCTAssertEqual(PaybackScale.around(3.2).ceiling, 5)
        XCTAssertEqual(PaybackScale.around(13.4).ceiling, 20)
        XCTAssertEqual(PaybackScale.around(60).ceiling, 100)
    }

    /// The whole point of the ladder: the fill never collapses to a stub, so
    /// the magnitude is carried by where the tick sits.
    func testTheFillStaysReadableAtEveryMagnitude() {
        for multiple in [1.1, 1.9, 3.2, 7.5, 13.4, 48.0, 260.0] {
            let scale = PaybackScale.around(multiple)
            let fill = scale.fill(multiple)
            XCTAssertGreaterThan(fill, 0.4, "\(multiple)× drew as a stub")
            XCTAssertLessThanOrEqual(fill, 1.0)
            let tick = try? XCTUnwrap(scale.breakEven)
            XCTAssertNotNil(tick, "\(multiple)× lost its break-even tick")
        }
    }

    func testBreakEvenSitsWhereOneTimesIs() {
        let scale = PaybackScale.around(3.2)      // ceiling 5
        XCTAssertEqual(try XCTUnwrap(scale.breakEven), 0.2, accuracy: 0.0001)
    }
}

/// Reading the ChatGPT plan out of Codex's identity token.
///
/// The token here is a hand-built, unsigned JWT: the app never verifies one, so
/// a test does not need a real signature either — and a real token has no place
/// in a repository.
final class CodexPlanDetectorTests: XCTestCase {
    private func token(claims: [String: Any]) throws -> String {
        let payload = try JSONSerialization.data(withJSONObject: claims)
        let encoded = payload.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "header.\(encoded).signature"
    }

    private func write(planType: String?, start: String? = nil) throws -> String {
        var auth: [String: Any] = ["chatgpt_account_id": "acct"]
        if let planType { auth["chatgpt_plan_type"] = planType }
        if let start { auth["chatgpt_subscription_active_start"] = start }
        let identity = try token(claims: ["https://api.openai.com/auth": auth])
        let file: [String: Any] = [
            "OPENAI_API_KEY": NSNull(),
            "tokens": ["id_token": identity, "access_token": "never-read",
                       "refresh_token": "never-read"]
        ]
        let path = NSTemporaryDirectory() + "codex-\(UUID().uuidString).json"
        try JSONSerialization.data(withJSONObject: file).write(to: URL(fileURLWithPath: path))
        return path
    }

    func testItReadsThePlanAndTheBillingDay() throws {
        let path = try write(planType: "plus", start: "2026-04-22T21:50:20+00:00")
        let plan = try XCTUnwrap(PlanDetector.detectCodex(path: path))
        XCTAssertEqual(plan.planID, "chatgpt_plus")
        XCTAssertEqual(plan.name, "ChatGPT Plus")
        XCTAssertEqual(plan.monthlyUSD, 20)
        XCTAssertEqual(plan.renewalDay, 22)
    }

    func testProIsWorthTenTimesPlus() throws {
        let path = try write(planType: "pro")
        let plan = try XCTUnwrap(PlanDetector.detectCodex(path: path))
        XCTAssertEqual(plan.monthlyUSD, 200)
    }

    /// A free account has nothing to weigh usage against, so it is not a plan.
    func testAFreeAccountIsNotAPlan() throws {
        XCTAssertNil(PlanDetector.detectCodex(path: try write(planType: "free")))
        XCTAssertNil(PlanDetector.detectCodex(path: try write(planType: nil)))
    }

    /// A plan type OpenAI adds later still names itself, it just cannot price
    /// itself — which is better than being invisible.
    func testAnUnknownPlanIsStillNamed() throws {
        let plan = try XCTUnwrap(PlanDetector.detectCodex(path: try write(planType: "ultra")))
        XCTAssertEqual(plan.name, "ChatGPT Ultra")
        XCTAssertNil(plan.monthlyUSD)
    }

    func testRubbishIsNotAPlan() throws {
        XCTAssertNil(PlanDetector.detectCodex(path: "/nowhere.json"))
        let path = NSTemporaryDirectory() + "codex-bad-\(UUID().uuidString).json"
        try "{\"tokens\":{\"id_token\":\"not-a-jwt\"}}".write(toFile: path, atomically: true,
                                                              encoding: .utf8)
        XCTAssertNil(PlanDetector.detectCodex(path: path))
    }

    /// Both timestamp shapes occur in the wild: Claude writes fractional
    /// seconds, OpenAI does not.
    func testBothTimestampShapesParse() {
        XCTAssertEqual(PlanDetector.day(ofISO: "2026-04-22T21:50:20+00:00"), 22)
        XCTAssertEqual(PlanDetector.day(ofISO: "2023-10-03T23:13:02.277543Z"), 3)
    }
}

/// Switching a ring on because a plan was found — once, and only once.
@MainActor
final class AutoEnableTests: XCTestCase {
    private func preferences() -> Preferences {
        let name = "AutoEnableTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return Preferences(defaults: defaults)
    }

    func testAFoundPlanSwitchesItsRingOn() {
        let p = preferences()
        XCTAssertTrue(p.enabledVendors.isEmpty)
        p.autoEnableRings(for: [.anthropic, .openai])
        XCTAssertEqual(p.enabledVendors, [.anthropic, .openai])
    }

    /// The one that matters: turning a ring off has to stay off. Without the
    /// separate record of what has already been offered, every launch would
    /// switch it back on and the setting would appear not to work at all.
    func testSwitchingOneOffKeepsItOff() {
        let p = preferences()
        p.autoEnableRings(for: [.anthropic])
        p.setRing(false, for: .anthropic)
        p.autoEnableRings(for: [.anthropic])          // as a later launch would
        XCTAssertFalse(p.showsRing(for: .anthropic))
    }

    /// A plan found for the first time later on still gets its ring, even
    /// though others have already had theirs.
    func testANewlyFoundPlanIsStillWelcome() {
        let p = preferences()
        p.autoEnableRings(for: [.anthropic])
        p.autoEnableRings(for: [.anthropic, .openai])
        XCTAssertEqual(p.enabledVendors, [.anthropic, .openai])
    }
}
