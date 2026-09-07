import Foundation

/// Fixed numbers for screenshots and for eyeballing the layout, reached with
/// `TOKNOTCH_DEMO=1`. Built through the same digest and builder the app uses,
/// so what a screenshot shows is what the real path produces — a hand-written
/// set of rings would drift from the real one silently.
enum Fixtures {
    /// A plan on one of the two vendors, so the payback group is exercised as
    /// well as the plain vendor card.
    static let plans: [Vendor: Subscription] = [
        .anthropic: Subscription(monthlyUSD: 200, renewalDay: 3)
    ]

    static func rings(language: AppLanguage = .chinese,
                      now: Date = Date(),
                      calendar: Calendar = .current) -> [RingSnapshot] {
        RingBuilder.rings(from: digest(now: now, calendar: calendar),
                          vendors: [.anthropic, .openai],
                          subscriptions: plans,
                          language: language, now: now, calendar: calendar)
    }

    static func digest(now: Date = Date(), calendar: Calendar = .current) -> UsageDigest {
        let key = DayKey(calendar: calendar)
        func day(_ offset: Int, output: Int64, cacheRead: Int64, cost: Double,
                 messages: Int, model: String) -> GraphReport.Day {
            let date = calendar.date(byAdding: .day, value: offset, to: now) ?? now
            let counts = TokenCounts(input: 300, output: output, cacheRead: cacheRead,
                                     cacheWrite: output / 4, reasoning: 0)
            return GraphReport.Day(
                date: key.day(date),
                tokenBreakdown: counts,
                clients: [.init(modelId: model, tokens: counts, cost: cost, messages: messages)],
                cost: cost, messages: messages
            )
        }

        var days: [GraphReport.Day] = [
            day(0, output: 443_927, cacheRead: 41_176_954, cost: 43.43, messages: 151,
                model: "claude-opus-5")
        ]
        // A month of history behind it, with one clear peak so the today ring
        // has something short of full to draw.
        for offset in 1...45 {
            let scale = Int64(offset % 7 + 1)
            days.append(day(-offset,
                            output: 300_000 * scale,
                            cacheRead: 20_000_000 * scale,
                            cost: 21.5 * Double(scale),
                            messages: 90 * Int(scale),
                            model: offset % 3 == 0 ? "gpt-5.6-terra" : "claude-sonnet-5"))
        }

        let lifetime = UsageReport(entries: [
            .init(model: "claude-sonnet-5", tokens: TokenCounts(input: 120_000_000, output: 9_000_000, cacheRead: 2_800_000_000, cacheWrite: 40_000_000), cost: 743.74, messages: 21_400),
            .init(model: "claude-opus-5",   tokens: TokenCounts(input: 90_000_000, output: 7_000_000, cacheRead: 2_200_000_000, cacheWrite: 30_000_000), cost: 1565.61, messages: 18_900),
            .init(model: "gpt-5.6-terra",   tokens: TokenCounts(input: 60_000_000, output: 5_000_000, cacheRead: 820_000_000, cacheWrite: 12_000_000), cost: 262.54, messages: 9_100),
            .init(model: "deepseek-v4-flash", tokens: TokenCounts(input: 40_000_000, output: 3_000_000, cacheRead: 2_600_000_000, cacheWrite: 9_000_000), cost: 21.73, messages: 12_200)
        ], messages: 78_264)

        return UsageDigest.build(graph: GraphReport(contributions: days),
                                 lifetime: lifetime, now: now, calendar: calendar)
    }
}
