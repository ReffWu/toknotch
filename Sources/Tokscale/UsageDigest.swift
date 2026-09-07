import Foundation

/// Everything the rings show, worked out once from the two reports.
///
/// Pure: given the same reports and the same `now`, it produces the same
/// digest. All the arithmetic that used to be scattered through a provider per
/// ring — milestones, shares, baselines, model tables — lives here, where it
/// can be tested without a notch, a timer or a subprocess.
struct UsageDigest: Equatable {
    let today: Period
    let month: Period
    let lifetime: Period
    /// Vendors this machine has actually used, busiest first. The settings list
    /// is built from this rather than from a hard-coded roster, so a ring is
    /// only ever offered for a company whose models you have really run.
    let vendors: [VendorUsage]
    /// The per-day history, kept so that a stretch of any shape can be sliced
    /// out of it later without another read. A billing period does not line up
    /// with a calendar month — a plan billed on the 3rd has paid for the 3rd to
    /// the 2nd — so `month` cannot answer for it.
    let days: [DayUsage]
    let generatedAt: Date

    struct DayUsage: Equatable {
        /// `yyyy-MM-dd`, tokscale's own key for which day a session fell on.
        let date: String
        let totals: Totals
        let models: [ModelUsage]
    }

    /// One vendor's usage over an arbitrary stretch of days.
    ///
    /// Keys are compared as strings rather than parsed back into dates: they
    /// are already the vendor's idea of which day a session belongs to, and
    /// re-deriving that through `Date` only introduces a time zone to get wrong.
    func totals(for vendor: Vendor, in period: BillingPeriod,
                calendar: Calendar = .current) -> Totals {
        let key = DayKey(calendar: calendar)
        let from = key.day(period.start)
        // Exclusive: the renewal day belongs to the period it starts.
        let until = key.day(period.end)
        return days
            .filter { $0.date >= from && $0.date < until }
            .flatMap(\.models)
            .filter { $0.vendor == vendor }
            .reduce(Totals()) { $0 + $1.totals }
    }

    // MARK: - Parts

    struct Totals: Equatable {
        var counts = TokenCounts()
        var cost: Double = 0
        var messages: Int = 0

        var tokens: Int64 { counts.total }

        static func + (a: Totals, b: Totals) -> Totals {
            Totals(counts: a.counts + b.counts, cost: a.cost + b.cost,
                   messages: a.messages + b.messages)
        }
    }

    struct ModelUsage: Equatable, Identifiable {
        let model: String
        let vendor: Vendor
        let totals: Totals
        var id: String { model }
    }

    struct VendorUsage: Equatable, Identifiable {
        let vendor: Vendor
        let totals: Totals
        /// This vendor's own models, busiest first.
        let models: [ModelUsage]
        var id: String { vendor.rawValue }
    }

    /// What a ring's arc is measured against.
    ///
    /// Always named, never implied. An arc at 70% means nothing until you can
    /// say 70% *of what*, and each of the three rings answers that differently
    /// — so the answer travels with the number instead of living in a comment.
    struct Baseline: Equatable {
        let value: Double
        /// Shown on the card, in the reader's language.
        let caption: (AppLanguage) -> String

        static func == (a: Baseline, b: Baseline) -> Bool {
            a.value == b.value && a.caption(.english) == b.caption(.english)
        }
    }

    struct Period: Equatable {
        let totals: Totals
        let models: [ModelUsage]
        let vendors: [VendorUsage]
        /// Nil when there is nothing honest to measure against — a first day
        /// with no history behind it, or a first month with no month before it.
        /// The ring then draws its track and no arc, rather than inventing a
        /// denominator.
        let baseline: Baseline?

        var fraction: Double? {
            guard let baseline, baseline.value > 0 else { return nil }
            return Double(totals.tokens) / baseline.value
        }
    }

    // MARK: - Building

    static func build(graph: GraphReport, lifetime report: UsageReport,
                      now: Date = Date(), calendar: Calendar = .current) -> UsageDigest {
        let days = graph.contributions
        let key = DayKey(calendar: calendar)

        // --- Today -----------------------------------------------------------
        let todayKey = key.day(now)
        let todayDays = days.filter { $0.date == todayKey }
        let todayTotals = totals(ofDays: todayDays)

        // Measured against the busiest day of the last thirty, today excluded:
        // the ring closes when you match your own best recent day, which is a
        // fact about you rather than a number picked out of the air. The
        // *busiest* rather than the median on purpose — this is a ring you are
        // trying to fill, so it should be hard to fill.
        let windowStart = key.day(calendar.date(byAdding: .day, value: -30, to: now) ?? now)
        let recentPeak = days
            .filter { $0.date >= windowStart && $0.date < todayKey }
            .map { $0.tokenBreakdown.total }
            .max() ?? 0
        let todayBaseline = recentPeak > 0
            ? Baseline(value: Double(recentPeak)) { lang in
                lang == .chinese ? "近 30 天最高日" : "your best day in 30"
              }
            : nil

        // --- This month ------------------------------------------------------
        let monthPrefix = key.month(now)
        let monthDays = days.filter { $0.date.hasPrefix(monthPrefix) }
        let monthTotals = totals(ofDays: monthDays)

        // Against the same stretch of last month, not the whole of it: on the
        // 6th, comparing six days to a full thirty would read as a collapse
        // every time a month turned over.
        let dayOfMonth = calendar.component(.day, from: now)
        let lastMonthPrefix = calendar.date(byAdding: .month, value: -1, to: now).map(key.month)
        let lastMonthToDate = lastMonthPrefix.map { prefix in
            days.filter { $0.date.hasPrefix(prefix) && key.dayNumber($0.date) <= dayOfMonth }
        } ?? []
        let lastMonthTokens = totals(ofDays: lastMonthToDate).tokens
        let monthBaseline = lastMonthTokens > 0
            ? Baseline(value: Double(lastMonthTokens)) { lang in
                lang == .chinese ? "上月同期" : "the same days last month"
              }
            : nil

        // --- Lifetime --------------------------------------------------------
        let lifetimeModels = merge(report.entries.map {
            ModelUsage(model: $0.model,
                       vendor: .inferred(fromModelID: $0.model),
                       totals: Totals(counts: $0.tokens, cost: $0.cost, messages: $0.messages))
        })
        let lifetimeTotals = Totals(
            counts: lifetimeModels.reduce(TokenCounts()) { $0 + $1.totals.counts },
            cost: lifetimeModels.reduce(0) { $0 + $1.totals.cost },
            // The per-entry counts are sessions rather than requests; the
            // report's own total is the figure tokscale stands behind.
            messages: report.messages
        )
        let milestone = nextMilestone(above: lifetimeTotals.tokens)
        let lifetimeBaseline = Baseline(value: Double(milestone)) { lang in
            lang == .chinese ? "下一个里程碑" : "the next milestone"
        }

        let lifetimeVendors = group(lifetimeModels)

        let history = days.map { day in
            DayUsage(date: day.date,
                     totals: Totals(counts: day.tokenBreakdown, cost: day.cost,
                                    messages: day.messages),
                     models: modelsOf(days: [day]))
        }

        return UsageDigest(
            today: Period(totals: todayTotals,
                          models: modelsOf(days: todayDays),
                          vendors: group(modelsOf(days: todayDays)),
                          baseline: todayBaseline),
            month: Period(totals: monthTotals,
                          models: modelsOf(days: monthDays),
                          vendors: group(modelsOf(days: monthDays)),
                          baseline: monthBaseline),
            lifetime: Period(totals: lifetimeTotals,
                             models: lifetimeModels,
                             vendors: lifetimeVendors,
                             baseline: lifetimeBaseline),
            vendors: lifetimeVendors,
            days: history,
            generatedAt: now
        )
    }

    /// The next round number above `value`, on a 1–2–5 ladder.
    ///
    /// A ladder rather than fixed rungs so it behaves the same at every scale:
    /// somebody 40M in is chasing 50M, somebody 15B in is chasing 20B, and
    /// neither has to be written down in advance.
    static func nextMilestone(above value: Int64) -> Int64 {
        guard value > 0 else { return 1_000_000 }
        var magnitude: Int64 = 1_000_000
        while magnitude <= Int64.max / 10 {
            for rung in [Int64(1), 2, 5] where magnitude * rung > value {
                return magnitude * rung
            }
            magnitude *= 10
        }
        return value
    }

    // MARK: - Aggregation

    private static func totals(ofDays days: [GraphReport.Day]) -> Totals {
        Totals(counts: days.reduce(TokenCounts()) { $0 + $1.tokenBreakdown },
               cost: days.reduce(0) { $0 + $1.cost },
               messages: days.reduce(0) { $0 + $1.messages })
    }

    private static func modelsOf(days: [GraphReport.Day]) -> [ModelUsage] {
        merge(days.flatMap(\.clients).map {
            ModelUsage(model: $0.modelId,
                       vendor: .inferred(fromModelID: $0.modelId),
                       totals: Totals(counts: $0.tokens, cost: $0.cost, messages: $0.messages))
        })
    }

    /// One row per model. The same model reached by two routes arrives as two
    /// lines and has to be added up, or the table lists `deepseek-v4-flash`
    /// three times and none of them is the real figure.
    private static func merge(_ models: [ModelUsage]) -> [ModelUsage] {
        var byName: [String: ModelUsage] = [:]
        for model in models {
            if let existing = byName[model.model] {
                byName[model.model] = ModelUsage(model: existing.model, vendor: existing.vendor,
                                                 totals: existing.totals + model.totals)
            } else {
                byName[model.model] = model
            }
        }
        return byName.values.sorted { $0.totals.tokens > $1.totals.tokens }
    }

    private static func group(_ models: [ModelUsage]) -> [VendorUsage] {
        Dictionary(grouping: models, by: \.vendor)
            .map { vendor, models in
                VendorUsage(vendor: vendor,
                            totals: models.reduce(Totals()) { $0 + $1.totals },
                            models: models.sorted { $0.totals.tokens > $1.totals.tokens })
            }
            .sorted { $0.totals.tokens > $1.totals.tokens }
    }
}

/// `yyyy-MM-dd` keys in the machine's own time zone, matching the strings
/// tokscale writes. String comparison rather than parsed dates on purpose:
/// these keys are already the vendor's idea of which day a session fell on,
/// and re-deriving that through `Date` only introduces a time zone to get
/// wrong.
struct DayKey {
    private let dayFormatter: DateFormatter
    private let monthFormatter: DateFormatter

    init(calendar: Calendar = .current) {
        dayFormatter = DateFormatter()
        dayFormatter.calendar = calendar
        dayFormatter.timeZone = calendar.timeZone
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "yyyy-MM-dd"

        monthFormatter = DateFormatter()
        monthFormatter.calendar = calendar
        monthFormatter.timeZone = calendar.timeZone
        monthFormatter.locale = Locale(identifier: "en_US_POSIX")
        monthFormatter.dateFormat = "yyyy-MM"
    }

    func day(_ date: Date) -> String { dayFormatter.string(from: date) }
    func month(_ date: Date) -> String { monthFormatter.string(from: date) }

    /// The day-of-month out of a `yyyy-MM-dd` key.
    func dayNumber(_ key: String) -> Int {
        Int(key.suffix(2)) ?? 0
    }
}
