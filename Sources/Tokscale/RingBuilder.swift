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
        // Ordered by `RingKind.primaries` rather than listed here, so the stack
        // and the settings list cannot disagree about the order.
        var rings: [RingSnapshot] = RingKind.primaries.map { kind in
            let slice: UsageDigest.Period
            switch kind {
            case .month:    slice = digest.month
            case .lifetime: slice = digest.lifetime
            default:        slice = digest.today
            }
            return period(kind, slice, digest, language, now, calendar)
        }
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
        case .today:    (title, glyph) = (language.t("ring.today.title"), .today)
        case .month:    (title, glyph) = (language.t("ring.month.title"), .month)
        case .lifetime: (title, glyph) = (language.t("ring.lifetime.title"), .lifetime)
        case .vendor(let v): (title, glyph) = (v.title(language), .vendor(v))
        }
        return RingSnapshot(
            kind: kind, title: title, caption: "",
            glyph: glyph, headline: "—",
            hero: "—", heroCaption: "", heroTint: Palette.textSecondary,
            fraction: nil, tint: Palette.textSecondary, rows: [],
            note: note ?? language.t("status.reading")
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
            title = language.t("ring.today.title")
            glyph = .today
            caption = UsageFormat.day(now, language, calendar: calendar)
            measure = against(period, language)
        case .month:
            title = language.t("ring.month.title")
            glyph = .month
            // Month name and day count as separate values: they go in opposite
            // orders — "9月1–7日" against "1–7 Sep".
            caption = language.t("ring.month.caption",
                                 monthName(now, language, calendar),
                                 calendar.component(.day, from: now))
            measure = against(period, language)
        default:
            let milestone = period.baseline.map { Int64($0.value) } ?? 0
            title = language.t("ring.lifetime.title")
            glyph = .lifetime
            caption = language.t("ring.lifetime.caption")
            measure = language.t("ring.lifetime.measure",
                                 UsageFormat.tokens(milestone, language),
                                 percent(period.fraction, language))
        }

        return RingSnapshot(
            kind: kind, title: title, caption: caption, glyph: glyph,
            headline: tokens,
            hero: tokens, heroCaption: measure, heroTint: band.color,
            heroFraction: period.fraction,
            fraction: period.fraction, tint: band.color,
            rows: standing(period, language),
            modelRows: modelRows(period.models, of: period.totals.tokens, language),
            moreFormat: language.t("card.moreModels")
        )
    }

    /// The one line that says what the hero was measured against.
    private static func against(_ period: UsageDigest.Period,
                                _ language: AppLanguage) -> String {
        guard let baseline = period.baseline else {
            return language.t("baseline.none")
        }
        return language.t("baseline.against",
                          language.t(baseline.captionKey),
                          percent(period.fraction, language))
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
                          label: language.t("row.lifetimeUsage"),
                          value: "\(tokens) · \(UsageFormat.money(usage.totals.cost, language))",
                          startsGroup: true)
            ]
                let verdict = language.t(payback.hasPaidBack ? "payback.paidBack"
                                                          : "payback.onTheWay")
            return RingSnapshot(
                kind: .vendor(usage.vendor), title: usage.vendor.title(language),
                caption: periodLabel(payback, language, calendar),
                glyph: .vendor(usage.vendor),
                headline: tokens,
                hero: UsageFormat.multiple(payback.multiple, language),
                heroCaption: language.t("payback.hero",
                                        verdict,
                                        UsageFormat.money(payback.earned, language),
                                        UsageFormat.money(payback.subscription.monthlyUSD, language)),
                heroTint: payback.hasPaidBack ? Palette.paidBack : Palette.onTheWay,
                heroFraction: payback.scale.fill(payback.multiple),
                heroMarker: payback.scale.breakEven,
                fraction: share, tint: usage.vendor.ringTint,
                rows: rows,
                modelRows: modelRows(usage.models, of: usage.totals.tokens, language,
                                     tint: usage.vendor.ringTint),
                moreFormat: language.t("card.moreModels")
            )
        }

        var rows: [MetricRow] = [
            MetricRow(id: "cost",
                      label: language.t("row.equivalentCost"),
                      value: UsageFormat.money(usage.totals.cost, language))
        ]
        return RingSnapshot(
            kind: .vendor(usage.vendor), title: usage.vendor.title(language),
            caption: language.t("vendor.allTime"),
            glyph: .vendor(usage.vendor),
            headline: tokens,
            hero: tokens,
            heroCaption: language.t("vendor.share", UsageFormat.share(share, language)),
            heroTint: usage.vendor.ringTint,
            heroFraction: share,
            fraction: share, tint: usage.vendor.ringTint,
            rows: rows,
            modelRows: modelRows(usage.models, of: usage.totals.tokens, language,
                                 tint: usage.vendor.ringTint),
            moreFormat: language.t("card.moreModels")
        )
    }

    private static func periodLabel(_ payback: Payback, _ language: AppLanguage,
                                    _ calendar: Calendar) -> String {
        language.t("payback.period",
                   UsageFormat.day(payback.period.start, language, calendar: calendar))
    }

    // MARK: - Supporting rows

    /// What is worth keeping under the hero, and nothing else.
    ///
    /// The token split — output, input, cache — used to live here and has been
    /// dropped: it is the most technical line on the card and the least likely
    /// to be the reason anybody opened it. Money and volume stay, because those
    /// are the two things the hero is usually being weighed against.
    private static func standing(_ period: UsageDigest.Period,
                                 _ language: AppLanguage) -> [MetricRow] {
        [
            MetricRow(id: "cost",
                      label: language.t("row.equivalentCost"),
                      value: UsageFormat.money(period.totals.cost, language)),
            MetricRow(id: "messages",
                      label: language.t("row.requests"),
                      value: UsageFormat.count(period.totals.messages, language))
        ]
    }

    /// Every model, busiest first, each with the share of this period it
    /// accounts for.
    ///
    /// Not trimmed to what a card shows: the card decides that, and it depends
    /// on the screen and on whether the reader has asked for more. Capped only
    /// at the point where a list has stopped being a list.
    private static func modelRows(_ models: [UsageDigest.ModelUsage],
                                  of total: Int64,
                                  _ language: AppLanguage,
                                  tint: Color? = nil) -> [MetricRow] {
        guard total > 0 else { return [] }
        return models.prefix(NotchLayout.modelCeiling).enumerated().map { index, model in
            let share = Double(model.totals.tokens) / Double(total)
            return MetricRow(
                id: "model.\(index)",
                label: UsageFormat.modelName(model.model),
                value: "\(UsageFormat.tokens(model.totals.tokens, language)) · \(UsageFormat.moneyShort(model.totals.cost, language))",
                fraction: share,
                tint: tint ?? model.vendor.ringTint,
                startsGroup: index == 0
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

    private static func percent(_ fraction: Double?, _ language: AppLanguage) -> String {
        fraction.map { UsageFormat.percent($0, language) } ?? "—"
    }

    /// Just the month, named the way this language names it.
    private static func monthName(_ date: Date, _ language: AppLanguage,
                                  _ calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = language.locale
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        return formatter.string(from: date)
    }
}
