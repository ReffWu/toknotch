import Foundation
import SwiftUI

/// Turns a digest into the rings on screen.
///
/// Every string a person reads is decided here, in one place and in both
/// languages. The views below this take formatted text and draw it; they never
/// decide what a number means, and they never do arithmetic on it.
enum RingBuilder {
    /// How many models a card lists before it stops being glanceable.
    static let modelsPerCard = 3

    /// The fullest card: the two standing facts plus the model table.
    static let maxRowsPerCard = 2 + modelsPerCard

    static func rings(from digest: UsageDigest,
                      vendors enabled: Set<Vendor>,
                      subscriptions: [Vendor: Subscription] = [:],
                      language: AppLanguage,
                      now: Date = Date(),
                      calendar: Calendar = .current) -> [RingSnapshot] {
        var rings: [RingSnapshot] = [
            period(.today, digest.today, digest, language, now, calendar),
            period(.month, digest.month, digest, language, now, calendar),
            period(.lifetime, digest.lifetime, digest, language, now, calendar)
        ]
        // In the order the digest found them — busiest vendor first — so
        // turning several on gives a stack that reads as a ranking.
        rings += digest.vendors
            .filter { enabled.contains($0.vendor) }
            .map { usage in
                vendor(in: usage, of: digest,
                       subscription: subscriptions[usage.vendor].flatMap { $0.isActive ? $0 : nil },
                       language, now, calendar)
            }
        return rings
    }

    /// What a ring shows before the first read lands, or when nothing can be
    /// read at all. Deliberately still a ring: the stack keeps its shape, so a
    /// failed refresh does not rearrange the notch under the reader.
    static func placeholder(_ kind: RingKind, language: AppLanguage,
                            note: String? = nil) -> RingSnapshot {
        let (title, glyph): (String, RingGlyph)
        switch kind {
        case .today:    (title, glyph) = (zh(language, "今日", "Today"), .today)
        case .month:    (title, glyph) = (zh(language, "本月", "This month"), .month)
        case .lifetime: (title, glyph) = (zh(language, "累计", "All time"), .lifetime)
        case .vendor(let v): (title, glyph) = (v.title(language), .vendor(v))
        }
        return RingSnapshot(
            kind: kind, title: title, caption: "",
            glyph: glyph, headline: "—",
            hero: "—", heroCaption: "", heroTint: Palette.textSecondary,
            fraction: nil, tint: Palette.textSecondary, rows: [],
            note: note ?? zh(language, "正在读取 tokscale 数据…", "Reading tokscale data…")
        )
    }

    // MARK: - The three primaries

    /// All three read the same way: how much, measured against something named.
    private static func period(_ kind: RingKind, _ period: UsageDigest.Period,
                               _ digest: UsageDigest, _ language: AppLanguage,
                               _ now: Date, _ calendar: Calendar) -> RingSnapshot {
        let tokens = UsageFormat.tokens(period.totals.tokens, language)
        let band = IntensityBand.band(for: period.fraction)

        let (title, glyph, caption, measure): (String, RingGlyph, String, String)
        switch kind {
        case .today:
            title = zh(language, "今日", "Today")
            glyph = .today
            caption = date(now, language, calendar)
            measure = against(period, language)
        case .month:
            let day = calendar.component(.day, from: now)
            title = zh(language, "本月", "This month")
            glyph = .month
            caption = zh(language, "\(calendar.component(.month, from: now)) 月 1–\(day) 日",
                                   "1–\(day) \(monthName(now, language, calendar))")
            measure = against(period, language)
        default:
            let milestone = period.baseline.map { Int64($0.value) } ?? 0
            title = zh(language, "累计", "All time")
            glyph = .lifetime
            caption = zh(language, "全部时间", "everything")
            measure = zh(language,
                "距 \(UsageFormat.tokens(milestone, language)) 里程碑 \(percent(period.fraction))",
                "\(percent(period.fraction)) of the way to \(UsageFormat.tokens(milestone, language))")
        }

        return RingSnapshot(
            kind: kind, title: title, caption: caption, glyph: glyph,
            headline: tokens,
            hero: tokens, heroCaption: measure, heroTint: band.color,
            heroFraction: period.fraction,
            fraction: period.fraction, tint: band.color,
            rows: supporting(period, language)
        )
    }

    /// The one line that says what the hero was measured against.
    private static func against(_ period: UsageDigest.Period,
                                _ language: AppLanguage) -> String {
        guard let baseline = period.baseline else {
            return zh(language, "暂无可比的历史", "nothing to compare yet")
        }
        return zh(language, "\(baseline.caption(language))的 \(percent(period.fraction))",
                            "\(percent(period.fraction)) of \(baseline.caption(language))")
    }

    // MARK: - Vendor rings

    private static func vendor(in usage: UsageDigest.VendorUsage,
                               of digest: UsageDigest,
                               subscription: Subscription?,
                               _ language: AppLanguage,
                               _ now: Date,
                               _ calendar: Calendar) -> RingSnapshot {
        let lifetime = max(1, digest.lifetime.totals.tokens)
        let share = Double(usage.totals.tokens) / Double(lifetime)
        let tokens = UsageFormat.tokens(usage.totals.tokens, language)

        let payback = subscription.map { plan -> Payback in
            let period = BillingPeriod.current(renewalDay: plan.renewalDay,
                                               now: now, calendar: calendar)
            return Payback(subscription: plan, period: period,
                           earned: digest.totals(for: usage.vendor, in: period,
                                                 calendar: calendar).cost)
        }

        // With a plan, the question this card answers is "has it paid for
        // itself this period" — so that is the hero, and the lifetime figures
        // move below the rule. Without one, the question is simply how much
        // this vendor accounts for.
        if let payback {
            var rows: [MetricRow] = [
                MetricRow(id: "lifetime",
                          label: zh(language, "累计用量", "All-time usage"),
                          value: "\(tokens) · \(UsageFormat.money(usage.totals.cost))",
                          startsGroup: true)
            ]
            rows += modelRows(usage.models, of: usage.totals.tokens, language,
                              tint: usage.vendor.ringTint)

            let verdict = payback.hasPaidBack
                ? zh(language, "已回本", "paid back")
                : zh(language, "回本进行中", "on the way back")
            return RingSnapshot(
                kind: .vendor(usage.vendor), title: usage.vendor.title(language),
                caption: periodLabel(payback, language, calendar),
                glyph: .vendor(usage.vendor),
                headline: tokens,
                hero: String(format: "%.1f×", payback.multiple),
                heroCaption: zh(language,
                    "\(verdict) · 本期 \(UsageFormat.money(payback.earned)) / 订阅 \(UsageFormat.money(payback.subscription.monthlyUSD))",
                    "\(verdict) · \(UsageFormat.money(payback.earned)) earned on \(UsageFormat.money(payback.subscription.monthlyUSD))"),
                heroTint: payback.hasPaidBack ? IntensityBand.record.color : IntensityBand.strong.color,
                heroFraction: payback.scale.fill(payback.multiple),
                heroMarker: payback.scale.breakEven,
                fraction: share, tint: usage.vendor.ringTint,
                rows: rows
            )
        }

        var rows: [MetricRow] = [
            MetricRow(id: "cost",
                      label: zh(language, "等效商业价值", "Equivalent API cost"),
                      value: UsageFormat.money(usage.totals.cost))
        ]
        rows += modelRows(usage.models, of: usage.totals.tokens, language,
                          tint: usage.vendor.ringTint)

        return RingSnapshot(
            kind: .vendor(usage.vendor), title: usage.vendor.title(language),
            caption: zh(language, "累计", "All time"),
            glyph: .vendor(usage.vendor),
            headline: tokens,
            hero: tokens,
            heroCaption: zh(language, "占全部用量 \(UsageFormat.share(share))",
                                      "\(UsageFormat.share(share)) of everything"),
            heroTint: usage.vendor.ringTint,
            heroFraction: share,
            fraction: share, tint: usage.vendor.ringTint,
            rows: rows
        )
    }

    private static func periodLabel(_ payback: Payback, _ language: AppLanguage,
                                    _ calendar: Calendar) -> String {
        let start = payback.period.start
        let month = calendar.component(.month, from: start)
        let day = calendar.component(.day, from: start)
        return zh(language, "本期 \(month) 月 \(day) 日起",
                            "since \(day) \(monthName(start, language, calendar))")
    }

    // MARK: - Supporting rows

    /// What is worth keeping under the hero, and nothing else.
    ///
    /// The token split — output, input, cache — used to live here and has been
    /// dropped: it is the most technical line on the card and the least likely
    /// to be the reason anybody opened it. Money and volume stay, because those
    /// are the two things the hero is usually being weighed against.
    private static func supporting(_ period: UsageDigest.Period,
                                   _ language: AppLanguage) -> [MetricRow] {
        var rows: [MetricRow] = [
            MetricRow(id: "cost",
                      label: zh(language, "等效商业价值", "Equivalent API cost"),
                      value: UsageFormat.money(period.totals.cost)),
            MetricRow(id: "messages",
                      label: zh(language, "请求次数", "Requests"),
                      value: UsageFormat.count(period.totals.messages))
        ]
        rows += modelRows(period.models, of: period.totals.tokens, language)
        return rows
    }

    /// The busiest models, each with the share of this period it accounts for.
    private static func modelRows(_ models: [UsageDigest.ModelUsage],
                                  of total: Int64,
                                  _ language: AppLanguage,
                                  tint: Color? = nil) -> [MetricRow] {
        guard total > 0 else { return [] }
        return models.prefix(modelsPerCard).enumerated().map { index, model in
            let share = Double(model.totals.tokens) / Double(total)
            return MetricRow(
                id: "model.\(index)",
                label: UsageFormat.modelName(model.model),
                value: "\(UsageFormat.tokens(model.totals.tokens, language)) · \(UsageFormat.moneyShort(model.totals.cost))",
                fraction: share,
                tint: tint ?? model.vendor.ringTint,
                startsGroup: index == 0 && tint == nil
            )
        }
    }

    /// `44.4万 · 302 · 4118万` — the three token kinds in the order they matter:
    /// what was written for you, what you sent, and what was served from cache.
    private static func split(_ counts: TokenCounts, _ language: AppLanguage) -> String {
        let cache = counts.cacheRead + counts.cacheWrite
        return [counts.output, counts.input, cache]
            .map { UsageFormat.tokens($0, language) }
            .joined(separator: " · ")
    }

    /// A comparison ring explains itself by naming what it is compared against.
    private static func detail(for period: UsageDigest.Period,
                               _ language: AppLanguage) -> String {
        guard let baseline = period.baseline else {
            return zh(language, "暂无可比的历史", "nothing to compare yet")
        }
        return zh(language,
                  "\(baseline.caption(language))的 \(percent(period.fraction))",
                  "\(percent(period.fraction)) of \(baseline.caption(language))")
    }

    private static func percent(_ fraction: Double?) -> String {
        fraction.map(UsageFormat.percent) ?? "—"
    }

    private static func date(_ date: Date, _ language: AppLanguage,
                             _ calendar: Calendar) -> String {
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        return language == .chinese ? "\(month) 月 \(day) 日" : "\(day) \(monthName(date, language, calendar))"
    }

    private static func monthName(_ date: Date, _ language: AppLanguage,
                                  _ calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: language == .chinese ? "zh_CN" : "en_US")
        formatter.dateFormat = language == .chinese ? "M月" : "MMM"
        return formatter.string(from: date)
    }

    private static func zh(_ language: AppLanguage, _ chinese: String, _ english: String) -> String {
        language == .chinese ? chinese : english
    }
}
