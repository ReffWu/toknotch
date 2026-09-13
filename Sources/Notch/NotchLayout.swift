import AppKit

/// Every measurement is quoted in design-frame pixels so it can be checked
/// against `docs/design/frame-124-hover-tooltip.png` directly.
enum NotchLayout {
    // The notch body
    /// The depth the design frame fixes: a 44pt ring with an even margin
    /// either side of it.
    static let sideBodyDepth = Design.px(186)

    /// How deep the notch is, which is **not** the same on every edge.
    ///
    /// Turning the stack is more than a rotation. The percent label sits below
    /// its ring, so on a side edge it spends the stack's *length* — the ring
    /// leads the cell and the label follows it down. Turn the stack horizontal
    /// and the label has nowhere to go but into the notch's *depth*, and 70pt
    /// no longer fits a ring, a gap and a line of type. So a horizontal notch
    /// is deeper, and it keeps the frame's margin around the ring to stay
    /// recognisably the same object.
    static func bodyDepth(for edge: NotchEdge) -> CGFloat {
        edge.isVertical ? sideBodyDepth : 2 * sideRingMargin + cellExtent
    }

    /// Clear space between the ring and the bezel, from the design frame.
    private static var sideRingMargin: CGFloat { (sideBodyDepth - ringDiameter) / 2 }

    /// The same margin on every edge — on a horizontal one it is the gap above
    /// the ring rather than beside it, but it is the same distance.
    static func ringMargin(for edge: NotchEdge) -> CGFloat { sideRingMargin }

    static let curlRadius   = Design.px(103)
    /// The small inverse corner where a flush bar meets the screen's frame.
    ///
    /// The hardware notch is moulded into the bezel rather than cut out of it,
    /// and a bar that meets the frame with a raw square edge does not read that
    /// way. Deliberately a fraction of `curlRadius`: enough to round the join,
    /// nowhere near enough to taper the bar the way a full flare would.
    static let bezelFillet  = Design.px(28)
    static let cornerRadius = Design.px(78.8)
    static let padTop       = Design.px(69.5)   // body top -> first ring
    static let padBottom    = Design.px(50.1)   // last label -> body bottom
    static let cellSpacing  = Design.px(83.5)   // label bottom -> next ring top

    // The resting pill. Not in the design frame — it is the notch folded away,
    // sized to read as a deliberate handle rather than a sliver of chrome.
    static let pillWidth  = Design.px(26)
    static let pillHeight = Design.px(210)
    /// The pill is small, so the region that wakes it is deliberately larger
    /// *along* the edge — a sliver on a screen edge is a fiddly thing to aim at.
    static let pillHotZone = Design.px(90)
    /// How far the wake region reaches *inward* from the bezel, past the resting
    /// shape. Kept small on purpose: a generous inward reach means the notch
    /// opens while the pointer is still well clear of it, and directly under the
    /// display's notch that band is exactly where a browser's tab strip lives.
    static let pillReachInward = Design.px(16)

    // A provider cell
    static let ringDiameter  = Design.px(117)   // 44pt, the design spec's anchor
    static let trackStroke   = Design.px(15.5)
    static let progressStroke = Design.px(8)
    static let glyphSize     = Design.px(46)
    static let ringLabelGap  = Design.px(26.9)

    // The activity indicator. Not in the design frame — sized to sit in the gap
    // between the glyph (46px across) and the inside edge of the track (86px),
    // so it never crowds either.
    static let activityDiameter = Design.px(72)
    static let activityStroke   = Design.px(5.5)

    // The settings orb: it lives *below* the notch, not inside it. At rest only
    // an arc of its edge is drawn, tucked into the corner the bottom flare
    // makes; on hover the same circle fills in and takes a gear. One circle,
    // two states — which is why the arc has to be a segment of it rather than a
    // decorative stroke that happens to sit nearby.
    // Measured off the reference frames, which are 2px per point — the notch
    // body is the familiar 70pt in both, and that fixes the scale.
    //
    // The important find: the resting arc is **concentric with the notch's own
    // bottom flare**, one radius inside it. That is what makes it follow the
    // contour of the edge instead of merely sitting near it, and it is why the
    // orb is centred on the flare's centre rather than on the body's axis.
    //
    //   flare : centre (edge - curlRadius, shapeBottom)   radius 38.5pt
    //   arc   : same centre                                radius 28.5pt
    //   disc  : same centre                                diameter 46.5pt
    static let orbDiameter = Design.px(124)
    static let orbStroke   = Design.px(18)
    /// Distance from the flare's curve in to the resting arc.
    static let orbGap      = Design.px(27)
    /// Radius of the resting arc: the flare's radius, less the gap.
    static var orbArcRadius: CGFloat { curlRadius - orbGap }
    /// The resting arc's circle when it traces a *convex* corner: outside the
    /// corner by the same gap it keeps inside a flare. Takes the corner the
    /// shape actually draws, which is not always `cornerRadius` — a bar drawn
    /// as the hardware notch caps it at the hardware's own rounding.
    static func orbConvexArcRadius(corner: CGFloat) -> CGFloat { corner + orbGap }

    /// How far off a convex corner the orb hangs, on each axis.
    ///
    /// A flush bar has no flare, so no pocket for the orb to nestle into: its
    /// far corner is convex, and an orb centred on that corner sits *inside*
    /// the black. It hangs off it instead — clear of the corner by the same
    /// `orbGap` the flared version uses, plus its own radius so the disc never
    /// overlaps the bar. Taken diagonally, so it reads as belonging to the
    /// corner rather than to one edge or the other.
    static func orbCornerOffset(corner: CGFloat) -> CGFloat {
        (corner + orbGap + orbDiameter / 2) / 2.0.squareRoot()
    }
    static let orbGlyph    = Design.px(56)
    /// What the arc scales to as it hides.
    ///
    /// The arc is concentric with the bottom flare, `orbGap` inside it, so
    /// growing its radius carries it outward along the normal and *into* the
    /// notch's black. Landing exactly on the flare is not enough — sitting on
    /// the boundary it is still half visible. It goes a full stroke past, so
    /// the line is genuinely buried and stops being drawable rather than
    /// merely becoming faint.
    ///
    /// Shrinking it instead pulled it toward its own centre, away from the
    /// notch. Its position meanwhile travels with the folding corner, see
    /// `NotchViewModel.orbFoldTravel`.
    static var orbMergeScale: CGFloat { (curlRadius + orbStroke) / orbArcRadius }
    /// Generous, like the pill's — it is a small target on a screen edge.
    static let orbHotZone  = Design.px(152)

    // The hover tooltip
    static let cardWidth     = Design.px(600)
    static let cardCorner    = Design.px(49.5)
    static let cardPadding   = Design.px(32)
    /// How far the tail reaches out from the card, and how broad its base is.
    ///
    /// Roughly one to two and a half. The wedge that shipped first was 75 x 87
    /// — deeper than it was wide — which is what made it read as a spike rather
    /// than as part of the card.
    static let tailLength    = Design.px(50)
    static let tailHeight    = Design.px(108)
    static let tailGap       = Design.px(28)    // tail tip -> notch body edge
    static let barHeight     = Design.px(10.5)
    /// The break-even tick cut into a payback bar.
    static let markerWidth   = Design.px(6)
    static let headerGap     = Design.px(17)    // glyph -> title
    static let headerToBlock = Design.px(21)
    static let labelToBar    = Design.px(16.8)
    static let barToUsed     = Design.px(17.8)
    static let blockSpacing  = Design.px(20)
    /// Around the hero figure: the card's answer, and the space that makes it
    /// read as one.
    static let heroGap           = Design.px(22)
    static let heroCaptionGap    = Design.px(6)
    static let heroBarGap        = Design.px(18)
    static let heroBarHeight     = Design.px(13)
    static let heroLineHeight: CGFloat = lineHeight(
        NSFont.systemFont(ofSize: Design.fontSize(capPixels: 64), weight: .semibold)
    )
    static let heroCaptionLineHeight: CGFloat = lineHeight(
        NSFont.systemFont(ofSize: Design.fontSize(capPixels: 20), weight: .medium)
    )

    /// Between the caption and the first row.
    static let captionGap  = Design.px(14)
    /// Between one metric row and the next.
    static let rowSpacing  = Design.px(18)
    /// Either side of the rule that separates two groups of rows.
    static let groupSpacing = Design.px(22)
    static let hairline    = Design.px(2.5)

    /// The percent label's line box. Fixed rather than intrinsic so the panel
    /// geometry can be worked out in AppKit before SwiftUI lays anything out.
    static let percentLineHeight: CGFloat = {
        let font = NSFont.systemFont(ofSize: Design.fontSize(capPixels: 27), weight: .semibold)
        return ceil(font.ascender - font.descender + font.leading)
    }()

    static let cardTitleLineHeight: CGFloat = lineHeight(
        NSFont.systemFont(ofSize: Design.fontSize(capPixels: 26), weight: .semibold)
    )
    /// The card's body face. Held rather than rebuilt at each use: the line
    /// height below and the wrap measurement in `bodyTextHeight` have to be
    /// measuring the same font, or the budget and the text disagree.
    static let cardBodyFont = NSFont.systemFont(
        ofSize: Design.fontSize(capPixels: 18), weight: .regular
    )
    static let cardBodyLineHeight: CGFloat = lineHeight(cardBodyFont)

    /// How wide a line of body text is inside the card.
    static var cardTextWidth: CGFloat { cardWidth - 2 * cardPadding }

    /// How tall a run of body text is once it has wrapped to that column.
    ///
    /// Measured, because a note is the one piece of card text whose length is
    /// not known here — it says what went wrong and what fixes it, and the
    /// longest of them runs to three lines. A budget that assumed one line
    /// clipped the part that said what to do, on exactly the card a reader is
    /// looking at because something is wrong.
    ///
    /// Rounded up to whole lines: the card's height is a stack of line boxes,
    /// and half a line of budget leaves the last one straddling the clip.
    static func bodyTextHeight(_ text: String) -> CGFloat {
        guard !text.isEmpty else { return cardBodyLineHeight }
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: cardTextWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: cardBodyFont]
        )
        let lines = max(1, Int((bounds.height / cardBodyLineHeight).rounded(.up)))
        return CGFloat(lines) * cardBodyLineHeight
    }

    /// The height SwiftUI actually draws one line of this font at.
    ///
    /// Rounded rather than ceiled. `ceil` overstates it by a point, and a card's
    /// height is a stack of these — so every line on it contributed a point of
    /// dead black at the bottom, which on a six-row card is a visible band of
    /// empty card under the last row. `LineHeightProbeTests` holds this against
    /// a genuinely rendered line so it cannot drift back.
    private static func lineHeight(_ font: NSFont) -> CGFloat {
        (font.ascender - font.descender + font.leading).rounded()
    }

    /// Ring plus its percent label.
    static var cellExtent: CGFloat { ringDiameter + ringLabelGap + percentLineHeight }

    /// What one cell claims along the stack.
    ///
    /// Down a side edge, the ring *and the label underneath it*: both are on
    /// this axis. Across a horizontal one the label has moved into the depth,
    /// so the cell is the ring alone. Giving the horizontal case the vertical
    /// figure leaves 27pt of nothing between every pair of rings, on top of the
    /// spacing the frame already puts there — which is what made the top and
    /// bottom bars read as far too spread out.
    static func cellAlong(for edge: NotchEdge) -> CGFloat {
        edge.isVertical ? cellExtent : ringDiameter
    }

    /// Ring centre to ring centre.
    static func cellPitch(for edge: NotchEdge) -> CGFloat {
        cellAlong(for: edge) + cellSpacing
    }

    /// Padding at the start and the end of the stack.
    ///
    /// Down a side edge these are the frame's own two numbers, and they should
    /// stay different: `padTop` measures the body's top to the first *ring*,
    /// `padBottom` measures the last *label* to the body's foot. They pad
    /// different things, so they are not the same size.
    ///
    /// Across a horizontal edge the label has moved off this axis and both ends
    /// are padding the same thing — a cell. Carrying the difference over there
    /// only pushes the stack off centre: with four rings it reads as a slightly
    /// heavy left end, and with one it is a ring visibly not in the middle of
    /// its own notch. So the two become one number, their mean, which leaves
    /// the bar exactly as long as it would have been.
    static func padStart(for edge: NotchEdge) -> CGFloat {
        edge.isVertical ? padTop : (padTop + padBottom) / 2
    }

    static func padEnd(for edge: NotchEdge) -> CGFloat {
        edge.isVertical ? padBottom : (padTop + padBottom) / 2
    }

    /// Distance from the start of the whole shape to cell `index`'s ring centre.
    ///
    /// The ring leads its cell on every edge — down a side one the label
    /// follows it along the stack, across a horizontal one there is nothing
    /// else on the stack at all.
    static func ringCenter(index: Int, edge: NotchEdge = .right,
                           flare: CGFloat = curlRadius) -> CGFloat {
        flare + padStart(for: edge) + ringDiameter / 2
            + CGFloat(index) * cellPitch(for: edge)
    }

    /// Height of the notch body for a given number of provider cells.
    static func bodyLength(cellCount: Int, edge: NotchEdge = .right) -> CGFloat {
        let start = padStart(for: edge), end = padEnd(for: edge)
        guard cellCount > 0 else { return start + end }
        return start
            + CGFloat(cellCount) * cellAlong(for: edge)
            + CGFloat(cellCount - 1) * cellSpacing
            + end
    }

    /// Centre of the settings orb: the same point the notch's bottom flare
    /// curves around, which is what makes the arc parallel that curve.
    static func orbCenterAlong(cellCount: Int, edge: NotchEdge = .right) -> CGFloat {
        shapeLength(cellCount: cellCount, edge: edge)
    }

    /// Distance in from the screen edge, matching the flare's centre.
    static var orbInsetFromEdge: CGFloat { curlRadius }

    /// Full shape length, flares included.
    ///
    /// `flare` is what the ends actually take, not what they might: a flush bar
    /// has only the small corner into the frame, and reserving a whole
    /// `curlRadius` there leaves some 56pt of dead black either side of the
    /// readings — which is exactly what made the top bar look too wide.
    static func shapeLength(cellCount: Int, edge: NotchEdge = .right,
                            flare: CGFloat = curlRadius) -> CGFloat {
        bodyLength(cellCount: cellCount, edge: edge) + 2 * flare
    }

    /// The tooltip's height for a card of `rowCount` rows, `barCount` of which
    /// draw a bar. Worked out here rather than left to SwiftUI, so the hover
    /// region and the panel can both be sized before the card is ever laid out.
    static func cardHeight(rowCount: Int, barCount: Int = 0, ruleCount: Int = 0,
                           hasHero: Bool = false, hasHeroBar: Bool = false,
                           hasMoreLine: Bool = false,
                           note: String? = nil) -> CGFloat {
        var height = 2 * cardPadding
        height += max(glyphSize, cardTitleLineHeight)

        if hasHero {
            height += heroGap + heroLineHeight + heroCaptionGap + heroCaptionLineHeight
            if hasHeroBar { height += heroBarGap + heroBarHeight }
        }

        // A note replaces everything else: when there is nothing to report,
        // saying so *is* the card.
        if let note {
            return height + headerToBlock + bodyTextHeight(note)
        }
        guard rowCount > 0 else { return height }

        let gaps = rowCount - 1
        height += headerToBlock
            + CGFloat(rowCount) * cardBodyLineHeight
            + CGFloat(barCount) * (labelToBar + barHeight)
            + CGFloat(max(0, gaps - ruleCount)) * rowSpacing
            + CGFloat(ruleCount) * (2 * groupSpacing + hairline)
        // The line offering the models that did not fit.
        if hasMoreLine { height += rowSpacing + cardBodyLineHeight }
        return height
    }

    /// How many model rows a card can show before it runs off the screen.
    ///
    /// Solved by walking up rather than by inverting `cardHeight`: that figure
    /// is a sum of a dozen named parts, and an inverted copy of it would have to
    /// be kept in step by hand. The range is short enough that the search costs
    /// nothing.
    static func modelsFitting(cardBudget: CGFloat, standingRows: Int) -> Int {
        var fits = 0
        for n in 1...modelCeiling {
            // Costed as though one were still hidden, so admitting the nth row
            // can never be what pushes the "more" line off the bottom.
            let height = cardHeight(rowCount: standingRows + n, barCount: n + 1,
                                    ruleCount: 1, hasHero: true, hasHeroBar: true,
                                    hasMoreLine: true)
            guard height <= cardBudget else { break }
            fits = n
        }
        return max(RingSnapshot.collapsedModels, fits)
    }

    /// Past this many rows the card has stopped being glanceable, and counting
    /// the rest is the kinder answer however much room the screen has.
    static let modelCeiling = 12

    /// The fullest card that can occur: a vendor with a subscription, which
    /// carries the payback group, the rule under it, the standing facts and the
    /// model table with a bar on every model row. The panel is sized once for
    /// the whole stack, so it has to hold whichever card turns out to be worst.
    static let maxRowCount = RingBuilder.maxRowsPerCard
    static let maxBarCount = RingBuilder.modelsPerCard + 1
    static let maxRuleCount = 1


    /// Costed with the "more" line present, because the fullest card a
    /// collapsed stack can produce is one that still has models to offer.
    static let defaultMaxCardHeight = cardHeight(
        rowCount: maxRowCount, barCount: maxBarCount, ruleCount: maxRuleCount,
        hasHero: true, hasHeroBar: true, hasMoreLine: true
    )

    /// Room at each end of the stack: enough for the settings orb to hang past
    /// the foot of the shape, and enough for a tooltip anchored to the first or
    /// last cell to still have somewhere to sit.
    ///
    /// Both orientations need half a card past each end, and for the same
    /// reason: the card is centred on the cell it belongs to, so hovering the
    /// first or last ring throws half the card past the stack. Which dimension
    /// crosses the ends is what differs — the card's height along a vertical
    /// edge, its width along a horizontal one.
    static func slack(for edge: NotchEdge,
                      maxCardHeight: CGFloat = defaultMaxCardHeight) -> CGFloat {
        edge.isVertical
            ? max(endSlack, maxCardHeight / 2 + cardCorner)
            : max(endSlack, cardWidth / 2 + cardCorner)
    }

    private static let endSlack = Design.px(190)

    /// How far the panel reaches inward from the bezel, past the notch itself,
    /// so the tooltip has somewhere to live. Beside the stack on a side edge,
    /// below or above it on a horizontal one.
    static func tooltipDepth(for edge: NotchEdge,
                             maxCardHeight: CGFloat = defaultMaxCardHeight) -> CGFloat {
        (edge.isVertical ? cardWidth : maxCardHeight) + tailLength + tailGap
    }
}
