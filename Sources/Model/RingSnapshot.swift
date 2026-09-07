import SwiftUI

/// Which ring this is. The identity is the kind, so a ring keeps its place in
/// the stack and its animation across refreshes.
enum RingKind: Equatable, Hashable {
    case today
    case month
    case lifetime
    case vendor(Vendor)

    var id: String {
        switch self {
        case .today:            return "today"
        case .month:            return "month"
        case .lifetime:         return "lifetime"
        case .vendor(let v):    return "vendor.\(v.rawValue)"
        }
    }

    /// The three that carry the app. Vendor rings are opt-in and follow them.
    static let primaries: [RingKind] = [.today, .month, .lifetime]
}

/// One row inside a card: a label, a figure, and optionally a bar.
struct MetricRow: Identifiable, Equatable {
    let id: String
    let label: String
    let value: String
    /// Drawn as a bar when present. Only ever a share of something named in the
    /// label — never a bare number dressed up as a proportion.
    var fraction: Double? = nil
    var tint: Color? = nil
    /// A tick drawn across the bar, 0...1. Marks break-even on a payback bar,
    /// so a multiple past 1 can still be read off the bar rather than only off
    /// the number beside the title.
    var marker: Double? = nil
    /// Draws a rule above this row. A vendor card answers two questions — what
    /// the plan has returned this period, and what the vendor has done overall
    /// — and running them together as one list reads as one list.
    var startsGroup: Bool = false
}

/// One ring, ready to draw. Everything is already formatted and localised: the
/// views do no arithmetic and make no decisions about wording.
struct RingSnapshot: Identifiable, Equatable {
    let kind: RingKind
    /// The card's heading — "今日" / "Today".
    let title: String
    /// The stretch this ring covers — "9月6日", "1–6 Sep". Sits on the title
    /// row, where it costs no height.
    let caption: String
    let glyph: RingGlyph
    /// What is printed under the ring. Tokens, per the设置 — money lives in
    /// the card's first row.
    let headline: String

    /// The one figure this card exists to give you, set large enough that it is
    /// the only thing you have to read.
    ///
    /// A card is opened with a question already in mind — "has this month paid
    /// for the plan yet?", "how much have I burned today?" — and the answer
    /// should not have to be picked out of a table of eight similar-looking
    /// rows in the same size type. Everything below the hero supports it; none
    /// of it competes.
    let hero: String
    /// What the hero figure means, in a few words.
    let heroCaption: String
    let heroTint: Color
    /// The bar under the hero, when the hero is a proportion of something.
    var heroFraction: Double? = nil
    /// Break-even, or any other point worth marking on that bar.
    var heroMarker: Double? = nil

    /// The arc. Nil when there is no honest denominator yet, in which case the
    /// ring shows its track alone.
    let fraction: Double?
    let tint: Color
    let rows: [MetricRow]
    /// Set when there is nothing to show — no tokscale, no data yet, a failed
    /// read. Replaces the rows rather than sitting alongside them.
    var note: String? = nil

    var id: String { kind.id }

    var hasReading: Bool { note == nil }

    /// Whether the hero carries a bar under it.
    var hasHeroBar: Bool { heroFraction != nil }

    /// The height this card draws at.
    ///
    /// Defined once, because it is needed in four places — the card itself, the
    /// hover region, the tooltip's position, and the panel's budget — and the
    /// moment two of them spell it out separately they drift. They already did:
    /// a copy that had not learnt about group rules reserved eleven points too
    /// few, which is a card whose bottom row cannot be reached with the mouse.
    var cardHeight: CGFloat {
        NotchLayout.cardHeight(
            rowCount: rows.count,
            barCount: rows.filter { $0.fraction != nil }.count,
            ruleCount: rows.dropFirst().filter(\.startsGroup).count,
            hasHero: note == nil,
            hasHeroBar: hasHeroBar,
            note: note
        )
    }
}
