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

    /// The three that carry the app, in the order they appear.
    ///
    /// Widest span first, narrowing to today. Reading down the stack then goes
    /// from what you have done overall to what you have done since this
    /// morning, which is how the numbers relate to each other — today is a
    /// slice of the month, which is a slice of the lifetime.
    static let primaries: [RingKind] = [.lifetime, .month, .today]
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
    /// The standing facts, always shown.
    let rows: [MetricRow]
    /// Every model this ring covers, busiest first — the whole list, not a
    /// selection. How many of them a card actually draws is a question about
    /// the screen and about whether the reader has asked for more, and neither
    /// of those belongs in the digest.
    var modelRows: [MetricRow] = []
    /// Set when there is nothing to show — no tokscale, no data yet, a failed
    /// read. Replaces the rows rather than sitting alongside them.
    var note: String? = nil

    var id: String { kind.id }

    var hasReading: Bool { note == nil }

    /// Whether the hero carries a bar under it.
    var hasHeroBar: Bool { heroFraction != nil }

    /// How many models a collapsed card lists before offering the rest.
    ///
    /// Three is what fits without the card becoming a table. Everything past it
    /// is a click away rather than gone — a list that silently stops at three
    /// makes a fourth model look like it does not exist.
    static let collapsedModels = 3

    /// The rows a card draws, given how many models it has room for.
    func rows(showingModels limit: Int) -> [MetricRow] {
        rows + modelRows.prefix(max(0, limit))
    }

    /// Models left over after `limit` — what the "more" line counts.
    func hiddenModels(after limit: Int) -> Int {
        max(0, modelRows.count - max(0, limit))
    }

    /// Format for the line offering the models that did not fit, with the count
    /// left for the card to fill in — how many are hidden depends on the screen,
    /// which the builder has no business knowing.
    var moreFormat: String = ""

    /// The height this card draws at.
    ///
    /// Defined once, because it is needed in four places — the card itself, the
    /// hover region, the tooltip's position, and the panel's budget — and the
    /// moment two of them spell it out separately they drift. They already did:
    /// a copy that had not learnt about group rules reserved eleven points too
    /// few, which is a card whose bottom row cannot be reached with the mouse.
    func cardHeight(showingModels limit: Int) -> CGFloat {
        let shown = rows(showingModels: limit)
        return NotchLayout.cardHeight(
            rowCount: shown.count,
            barCount: shown.filter { $0.fraction != nil }.count,
            ruleCount: shown.dropFirst().filter(\.startsGroup).count,
            hasHero: note == nil,
            hasHeroBar: hasHeroBar,
            hasMoreLine: hiddenModels(after: limit) > 0,
            note: note
        )
    }
}
