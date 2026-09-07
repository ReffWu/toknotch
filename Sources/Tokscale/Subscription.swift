import Foundation

/// What a vendor's plan costs and when it renews.
///
/// Entered by hand, and it has to be: reading a plan off an account would mean
/// holding that vendor's credentials, which is the one thing this app promises
/// not to do. Two numbers is a small price for keeping the keychain out of it.
struct Subscription: Codable, Equatable {
    /// What the plan costs each month, in USD — the same currency tokscale
    /// prices usage in, so the two are directly comparable.
    var monthlyUSD: Double
    /// The day of the month the plan renews on. Clamped into a real day when a
    /// month is too short for it, so a plan billed on the 31st still has a
    /// period in February.
    var renewalDay: Int
    /// Which catalogue entry this is, when it came from one — so the menu can
    /// show it selected, and so a detected plan can be told from a typed one.
    var planID: String?

    init(monthlyUSD: Double, renewalDay: Int = 1, planID: String? = nil) {
        self.monthlyUSD = monthlyUSD
        self.renewalDay = min(max(renewalDay, 1), 31)
        self.planID = planID
    }

    var isActive: Bool { monthlyUSD > 0 }
}

/// The stretch a subscription is currently paying for.
///
/// A calendar month is the wrong window for this: a plan billed on the 3rd has
/// paid for the 3rd to the 2nd, and judging it on what happened since the 1st
/// silently mixes in days the last payment covered. On the 2nd of the month
/// that is nearly a full period of somebody else's usage.
struct BillingPeriod: Equatable {
    let start: Date
    /// The day the next payment lands — exclusive, so the period is [start, end).
    let end: Date

    static func current(renewalDay: Int, now: Date = Date(),
                        calendar: Calendar = .current) -> BillingPeriod {
        let day = min(max(renewalDay, 1), 31)
        let today = calendar.component(.day, from: now)
        // This month's renewal has already happened, or it has not and the
        // period we are in started last month.
        let anchor = today >= clamped(day, in: now, calendar)
            ? now
            : calendar.date(byAdding: .month, value: -1, to: now) ?? now

        let start = date(day: day, in: anchor, calendar)
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: anchor) ?? anchor
        return BillingPeriod(start: start, end: date(day: day, in: nextMonth, calendar))
    }

    /// How far through the period we are, 0...1. Not shown as a number — it is
    /// what says whether a multiplier is impressive yet: 3× on the last day is
    /// a different fact from 3× on the second.
    func elapsed(now: Date = Date()) -> Double {
        let span = end.timeIntervalSince(start)
        guard span > 0 else { return 1 }
        return min(max(now.timeIntervalSince(start) / span, 0), 1)
    }

    /// A month billed on the 31st has no 31st in February; the renewal lands on
    /// the last day instead.
    private static func clamped(_ day: Int, in month: Date, _ calendar: Calendar) -> Int {
        let range = calendar.range(of: .day, in: .month, for: month) ?? 1..<29
        return min(day, range.upperBound - 1)
    }

    private static func date(day: Int, in month: Date, _ calendar: Calendar) -> Date {
        var components = calendar.dateComponents([.year, .month], from: month)
        components.day = clamped(day, in: month, calendar)
        components.hour = 0
        components.minute = 0
        components.second = 0
        return calendar.date(from: components) ?? month
    }
}

/// The range a payback bar is drawn against.
///
/// Break-even is the only point on this bar that means anything, and a bar that
/// simply fills up at 1× stops saying anything the moment it gets there: 1.1×
/// and 40× draw identically, and the reading you actually want — how far past
/// paying for itself this plan is — is the one thing it cannot show.
///
/// So the range climbs as the multiple does, and break-even is marked on it.
/// The ladder is 1, 2, 5, 10, 20, 50… rather than powers of ten: a plan at 3.2×
/// against a ceiling of 10 draws a third-full and reads as disappointing, when
/// it has in fact returned three times its cost. On this ladder the fill always
/// lands between half and full, and it is the tick's position that carries the
/// magnitude.
struct PaybackScale: Equatable {
    let ceiling: Double

    static func around(_ multiple: Double) -> PaybackScale {
        guard multiple > 1 else { return PaybackScale(ceiling: 1) }
        var magnitude: Double = 1
        while magnitude < 1e9 {
            for rung in [1.0, 2, 5] where magnitude * rung >= multiple {
                return PaybackScale(ceiling: magnitude * rung)
            }
            magnitude *= 10
        }
        return PaybackScale(ceiling: multiple)
    }

    /// How much of the bar is filled.
    func fill(_ multiple: Double) -> Double {
        ceiling > 0 ? min(max(multiple / ceiling, 0), 1) : 0
    }

    /// Where the break-even tick sits, 0...1. Nil while the ceiling *is* break
    /// even — a tick on the end of the bar says nothing the end does not.
    var breakEven: Double? { ceiling > 1 ? 1 / ceiling : nil }
}

/// How a subscription is doing against what it produced.
struct Payback: Equatable {
    let subscription: Subscription
    let period: BillingPeriod
    /// What this vendor's usage would have cost at published API prices, over
    /// this billing period.
    let earned: Double

    /// Earned over paid. 1.0 is break-even.
    var multiple: Double {
        subscription.monthlyUSD > 0 ? earned / subscription.monthlyUSD : 0
    }

    var hasPaidBack: Bool { multiple >= 1 }

    /// What is left to earn before the plan pays for itself, or what it has
    /// produced beyond it.
    var margin: Double { earned - subscription.monthlyUSD }

    var scale: PaybackScale { .around(multiple) }

    /// Where the plan would land if the rest of the period matched the rate so
    /// far. Only meaningful once a little of it has run — before that a single
    /// busy hour projects to absurd numbers.
    func projected(now: Date = Date()) -> Double? {
        let elapsed = period.elapsed(now: now)
        guard elapsed > 0.08 else { return nil }
        return earned / elapsed
    }
}
