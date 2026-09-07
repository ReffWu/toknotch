import XCTest
@testable import TokNotch

/// The aggregation every ring is built from.
final class UsageDigestTests: XCTestCase {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    /// 2026-09-06, a Sunday, six days into the month.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 6, hour: 14))!
    }

    private func day(_ offset: Int, tokens: Int64, cost: Double = 1,
                     messages: Int = 1, model: String = "claude-opus-5") -> GraphReport.Day {
        let date = calendar.date(byAdding: .day, value: offset, to: now)!
        let counts = TokenCounts(output: tokens)
        return GraphReport.Day(date: DayKey(calendar: calendar).day(date),
                               tokenBreakdown: counts,
                               clients: [.init(modelId: model, tokens: counts,
                                               cost: cost, messages: messages)],
                               cost: cost, messages: messages)
    }

    private func digest(_ days: [GraphReport.Day],
                        lifetime: UsageReport = UsageReport(entries: [], messages: 0)) -> UsageDigest {
        UsageDigest.build(graph: GraphReport(contributions: days), lifetime: lifetime,
                          now: now, calendar: calendar)
    }

    // MARK: - Slicing

    func testTodayIsOnlyToday() {
        let d = digest([day(0, tokens: 100), day(-1, tokens: 900), day(-2, tokens: 900)])
        XCTAssertEqual(d.today.totals.tokens, 100)
    }

    /// The month runs from the 1st, not over a trailing thirty days — a figure
    /// labelled "this month" that quietly includes late August is a lie.
    func testTheMonthStartsAtTheFirst() {
        let d = digest([day(0, tokens: 100),     // 6 Sep
                        day(-3, tokens: 100),    // 3 Sep
                        day(-8, tokens: 500)])   // 29 Aug — last month
        XCTAssertEqual(d.month.totals.tokens, 200)
    }

    // MARK: - Baselines

    /// The today ring closes when you match your own best recent day.
    func testTodayIsMeasuredAgainstTheBestOfTheLastThirty() {
        let d = digest([day(0, tokens: 50), day(-1, tokens: 100), day(-2, tokens: 40)])
        XCTAssertEqual(try XCTUnwrap(d.today.fraction), 0.5, accuracy: 0.0001)
    }

    /// Today's own figure must not become today's denominator, or the ring is
    /// pinned at 100% for ever.
    func testTodayIsNotItsOwnBaseline() {
        let d = digest([day(0, tokens: 900), day(-1, tokens: 100)])
        XCTAssertEqual(try XCTUnwrap(d.today.fraction), 9, accuracy: 0.0001)
    }

    /// Nothing behind it means no arc, rather than an invented one.
    func testAFirstDayHasNoBaseline() {
        XCTAssertNil(digest([day(0, tokens: 100)]).today.baseline)
        XCTAssertNil(digest([day(0, tokens: 100)]).today.fraction)
    }

    /// Six days in, the comparison is the first six days of last month — not
    /// the whole of it, or every month would open looking like a collapse.
    func testTheMonthIsMeasuredAgainstTheSameDaysLastMonth() {
        var days = [day(0, tokens: 100)]
        // 1–6 August: in the window. 7 August: past it, and must not count.
        for date in [1, 2, 3, 4, 5, 6] {
            let d = calendar.date(from: DateComponents(year: 2026, month: 8, day: date))!
            days.append(GraphReport.Day(date: DayKey(calendar: calendar).day(d),
                                        tokenBreakdown: TokenCounts(output: 25),
                                        clients: [], cost: 0, messages: 0))
        }
        let seventh = calendar.date(from: DateComponents(year: 2026, month: 8, day: 7))!
        days.append(GraphReport.Day(date: DayKey(calendar: calendar).day(seventh),
                                    tokenBreakdown: TokenCounts(output: 10_000),
                                    clients: [], cost: 0, messages: 0))

        let d = digest(days)
        XCTAssertEqual(try XCTUnwrap(d.month.baseline).value, 150, accuracy: 0.0001)
    }

    // MARK: - Milestones

    func testTheMilestoneLadderClimbsByOneTwoFive() {
        XCTAssertEqual(UsageDigest.nextMilestone(above: 15_434_419_444), 20_000_000_000)
        XCTAssertEqual(UsageDigest.nextMilestone(above: 40_000_000), 50_000_000)
        XCTAssertEqual(UsageDigest.nextMilestone(above: 900_000_000), 1_000_000_000)
        XCTAssertEqual(UsageDigest.nextMilestone(above: 0), 1_000_000)
    }

    func testTheMilestoneIsAlwaysAhead() {
        for value in [Int64(1), 999_999, 1_000_000, 2_000_000_000, 15_000_000_000] {
            XCTAssertGreaterThan(UsageDigest.nextMilestone(above: value), value)
        }
    }

    // MARK: - Totals

    /// `reasoning` is part of the total. Leaving it out is a silent undercount
    /// that makes the app disagree with tokscale's own headline for no visible
    /// reason — which is exactly what the previous version did.
    func testTheTotalIncludesReasoningTokens() {
        let counts = TokenCounts(input: 1, output: 2, cacheRead: 4,
                                 cacheWrite: 8, reasoning: 16)
        XCTAssertEqual(counts.total, 31)
    }

    func testLifetimeCountsEveryEntry() {
        let report = UsageReport(entries: [
            .init(model: "claude-opus-5", tokens: TokenCounts(output: 100), cost: 1, messages: 1),
            .init(model: "gpt-5.5", tokens: TokenCounts(output: 50), cost: 2, messages: 1)
        ], messages: 900)
        let d = digest([], lifetime: report)
        XCTAssertEqual(d.lifetime.totals.tokens, 150)
        XCTAssertEqual(d.lifetime.totals.cost, 3, accuracy: 0.0001)
        // The report's own total, not the per-entry sum: those count sessions.
        XCTAssertEqual(d.lifetime.totals.messages, 900)
    }

    // MARK: - Models and vendors

    /// The same model reached two ways is one row. Left unmerged the table
    /// lists `deepseek-v4-flash` three times and none of them is the real
    /// figure — which is what tokscale's own `provider` field produces.
    func testOneModelReachedTwoWaysIsOneRow() {
        let d = digest([day(0, tokens: 100, model: "deepseek-v4-flash"),
                        day(0, tokens: 50, model: "deepseek-v4-flash")])
        XCTAssertEqual(d.today.models.count, 1)
        XCTAssertEqual(d.today.models.first?.totals.tokens, 150)
    }

    func testModelsAreRankedBusiestFirst() {
        let d = digest([day(0, tokens: 10, model: "a"), day(0, tokens: 90, model: "b"),
                        day(0, tokens: 50, model: "c")])
        XCTAssertEqual(d.today.models.map(\.model), ["b", "c", "a"])
    }

    func testVendorsAreRankedBusiestFirst() {
        let report = UsageReport(entries: [
            .init(model: "gpt-5.5", tokens: TokenCounts(output: 10), cost: 0, messages: 0),
            .init(model: "claude-opus-5", tokens: TokenCounts(output: 90), cost: 0, messages: 0)
        ], messages: 0)
        XCTAssertEqual(digest([], lifetime: report).vendors.map(\.vendor), [.anthropic, .openai])
    }
}

/// Who built a model is worked out from its id, never from tokscale's
/// `provider` field — that field records the route, so on a real machine it
/// files one vendor under several names and credits models to companies that
/// had nothing to do with them.
final class VendorTests: XCTestCase {
    func testModelsMapToTheirMakers() {
        let cases: [(String, Vendor)] = [
            ("claude-opus-5", .anthropic), ("claude-sonnet-4-6", .anthropic),
            ("gpt-5.6-terra", .openai), ("gpt-5.4-mini", .openai),
            ("gemini-3.1-pro", .google), ("google/gemma-4-e4b", .google),
            ("deepseek-v4-flash-free", .deepseek), ("deepseek-v4-pro", .deepseek),
            ("qwen3.8-max-preview", .alibaba), ("Qwen3.6 35B-A3B UD-MLX (local)", .alibaba),
            ("qwopus3.6-35b-a3b-v1", .alibaba),
            ("glm-5.2", .zhipu), ("minimax-m3", .minimax), ("mimo-v2.5-free", .xiaomi),
            ("nemotron-3-ultra-free", .nvidia), ("grok-4", .xai), ("kimi-k2", .moonshot),
            ("unknown", .other), ("big-pickle", .other)
        ]
        for (model, expected) in cases {
            XCTAssertEqual(Vendor.inferred(fromModelID: model), expected, "\(model)")
        }
    }

    /// The case that made the old grouping wrong: Zhipu's GLM billed through an
    /// Alibaba plan, and DeepSeek reached through OpenCode. Neither route says
    /// anything about who wrote the model.
    func testTheRouteDoesNotDecideTheVendor() {
        XCTAssertEqual(Vendor.inferred(fromModelID: "glm-5.2"), .zhipu)
        XCTAssertEqual(Vendor.inferred(fromModelID: "deepseek-v4-flash"), .deepseek)
    }

    func testEveryVendorHasATitleInBothLanguages() {
        for vendor in Vendor.allCases {
            XCTAssertFalse(vendor.title(.chinese).isEmpty)
            XCTAssertFalse(vendor.title(.english).isEmpty)
        }
    }
}

/// Numbers are read at a glance and out of the corner of an eye.
final class UsageFormatTests: XCTestCase {
    func testChineseGroupsByWanAndYi() {
        XCTAssertEqual(UsageFormat.tokens(15_434_419_444, .chinese), "154亿")
        XCTAssertEqual(UsageFormat.tokens(43_500_007, .chinese), "4350万")
        XCTAssertEqual(UsageFormat.tokens(940_000_000, .chinese), "9.4亿")
        XCTAssertEqual(UsageFormat.tokens(302, .chinese), "302")
    }

    func testEnglishGroupsByThousands() {
        XCTAssertEqual(UsageFormat.tokens(15_434_419_444, .english), "15.4B")
        XCTAssertEqual(UsageFormat.tokens(43_500_007, .english), "43.5M")
        XCTAssertEqual(UsageFormat.tokens(302, .english), "302")
    }

    /// A model with a real but tiny share must not read as 0%, which looks like
    /// a bug rather than a small number.
    func testASmallShareKeepsADecimal() {
        XCTAssertEqual(UsageFormat.share(0.004), "0.4%")
        XCTAssertEqual(UsageFormat.share(0.402), "40%")
    }

    /// The vendor prefix has to survive: a primary card's model table mixes
    /// vendors, so `claude-opus-5` shortened to `opus-5` loses the one part of
    /// the name that says whose model it was.
    func testModelNamesKeepWhatIdentifiesThem() {
        XCTAssertEqual(UsageFormat.modelName("claude-opus-5"), "claude-opus-5")
        XCTAssertEqual(UsageFormat.modelName("gpt-5.6-terra"), "gpt-5.6-terra")
        XCTAssertEqual(UsageFormat.modelName("google/gemma-4-e4b"), "gemma-4-e4b")
        XCTAssertEqual(UsageFormat.modelName("Qwen3.6 35B-A3B (local)"), "Qwen3.6 35B-A3B")
        XCTAssertFalse(UsageFormat.modelName("unknown").isEmpty)
    }
}

/// The rings the stack actually shows.
final class RingBuilderTests: XCTestCase {
    private func rings(vendors: Set<Vendor>) -> [RingSnapshot] {
        RingBuilder.rings(from: Fixtures.digest(), vendors: vendors, language: .chinese)
    }

    func testTheThreePrimariesAlwaysComeFirst() {
        let ids = rings(vendors: []).map(\.id)
        XCTAssertEqual(ids, RingKind.primaries.map(\.id))
    }

    func testVendorRingsAreOptInAndFollowThePrimaries() {
        let ids = rings(vendors: [.anthropic]).map(\.id)
        XCTAssertEqual(ids.count, 4)
        XCTAssertEqual(ids.last, RingKind.vendor(.anthropic).id)
    }

    /// Every card has to say what its arc was measured against, or a ring at
    /// 70% means nothing.
    func testEveryRingExplainsItsOwnArc() {
        for ring in rings(vendors: [.anthropic, .openai]) {
            XCTAssertFalse(ring.caption.isEmpty, "\(ring.id) does not say what it measures")
            XCTAssertFalse(ring.headline.isEmpty)
        }
    }

    /// No card may carry more rows than the panel reserved room for.
    func testNoCardExceedsTheReservedHeight() {
        for ring in rings(vendors: Set(Vendor.allCases)) {
            XCTAssertLessThanOrEqual(ring.rows.count, NotchLayout.maxRowCount, ring.id)
            XCTAssertLessThanOrEqual(ring.cardHeight, NotchLayout.defaultMaxCardHeight, ring.id)
        }
    }

    /// A ring that could not be read still occupies its place, so a failed
    /// refresh does not rearrange the notch under the reader.
    func testAPlaceholderIsStillARing() {
        let ring = RingBuilder.placeholder(.today, language: .english, note: "nope")
        XCTAssertFalse(ring.hasReading)
        XCTAssertNil(ring.fraction)
        XCTAssertEqual(ring.id, RingKind.today.id)
    }
}
