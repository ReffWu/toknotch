import SwiftUI

/// The tail, aimed at the hovered cell.
///
/// Not a triangle. A straight-sided wedge meets the card at two hard corners
/// and ends in a needle point, which reads as a comic-book speech bubble stuck
/// onto a piece of Mac chrome — the two halves look like different objects.
///
/// This is the shape Apple's own popovers make instead: the silhouette leaves
/// the card *tangentially*, so there is no corner where they join, sweeps in,
/// and finishes on a rounded tip. It is also much shallower than it is wide,
/// which is what keeps it reading as a nib on the card rather than as a spike
/// coming off it.
private struct TooltipTail: Shape {
    /// Which way the card sits relative to the notch — the tip points back the
    /// other way, at the cell.
    let direction: NotchEdge.TooltipDirection

    /// How wide the tip is, as a fraction of the tail's half-width. Small
    /// enough to still read as a point; never zero, which is what makes a
    /// needle.
    private let tipFraction: CGFloat = 0.17

    func path(in rect: CGRect) -> Path {
        // Drawn once in its own frame — `reach` along the way it points, `span`
        // across — then mapped onto whichever axis this direction uses. One
        // curve to get right instead of four.
        let reach = pointsAlongX ? rect.width : rect.height
        let span  = pointsAlongX ? rect.height : rect.width
        let half = span / 2
        let tip = half * tipFraction

        var path = Path()
        // The base sits flat against the card; `place` maps (along, across)
        // into the rect, with `along` running from base (0) to tip (reach).
        path.move(to: place(0, -half, rect, reach, half))
        path.addCurve(
            to: place(reach - tip, -tip, rect, reach, half),
            // The first control point sits directly *above* the start, not
            // ahead of it: that makes the curve leave the base travelling along
            // the card's own edge, so the two share a tangent and the tail
            // swells out of the card instead of being stuck onto it. Pointing
            // this control outward instead is what put a pair of pinched
            // corners either side of the base.
            control1: place(0, -half * 0.38, rect, reach, half),
            control2: place(reach * 0.46, -tip * 2.3, rect, reach, half)
        )
        // The rounded tip.
        path.addQuadCurve(
            to: place(reach - tip, tip, rect, reach, half),
            control: place(reach, 0, rect, reach, half)
        )
        path.addCurve(
            to: place(0, half, rect, reach, half),
            control1: place(reach * 0.46, tip * 2.3, rect, reach, half),
            control2: place(0, half * 0.38, rect, reach, half)
        )
        path.closeSubpath()
        return path
    }

    private var pointsAlongX: Bool {
        direction == .leading || direction == .trailing
    }

    /// `along` runs from the base to the tip; `across` is signed, zero on the
    /// centre line.
    private func place(_ along: CGFloat, _ across: CGFloat,
                       _ rect: CGRect, _ reach: CGFloat, _ half: CGFloat) -> CGPoint {
        switch direction {
        case .leading:   // card on the left, tip to the right
            return CGPoint(x: rect.minX + along, y: rect.midY + across)
        case .trailing:  // card on the right, tip to the left
            return CGPoint(x: rect.maxX - along, y: rect.midY + across)
        case .down:      // card below, tip upward
            return CGPoint(x: rect.midX + across, y: rect.maxY - along)
        case .up:        // card above, tip downward
            return CGPoint(x: rect.midX + across, y: rect.minY + along)
        }
    }

    /// Shallow in the direction it points, broad across it.
    static func size(for direction: NotchEdge.TooltipDirection) -> CGSize {
        switch direction {
        case .leading, .trailing:
            return CGSize(width: NotchLayout.tailLength, height: NotchLayout.tailHeight)
        case .up, .down:
            return CGSize(width: NotchLayout.tailHeight, height: NotchLayout.tailLength)
        }
    }
}

/// The card chrome every tooltip shares: fixed width, the frame's padding and
/// corner, and the tail welded on so there is no seam between them.
private struct TooltipShell<Content: View>: View {
    /// Given explicitly rather than left to the contents.
    ///
    /// Sized by its contents, the card's height changes the instant they do —
    /// and the tail, centred on that height, jumps with it while the card's
    /// position is still gliding. The two halves then visibly come apart.
    let height: CGFloat
    /// Which side of the notch the card is on, so the tail goes on the other one.
    let direction: NotchEdge.TooltipDirection
    @ViewBuilder let content: Content

    private var card: some View {
        // The same arrangement that makes the notch fold work: the contents are
        // laid out once at their natural size and never move, and it is the
        // *mask* that changes size over them.
        //
        // The obvious alternative — putting the contents inside a frame of the
        // animating height — makes SwiftUI re-align them on every frame of the
        // animation, so the rows drift vertically inside the card and the top
        // ones slide out under the clip. Nothing should move here except the
        // boundary.
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: NotchLayout.cardCorner, style: .circular)
                .fill(Palette.card)
                .frame(width: NotchLayout.cardWidth, height: height)

            content
                .padding(NotchLayout.cardPadding)
                .frame(width: NotchLayout.cardWidth, alignment: .topLeading)
        }
        .frame(width: NotchLayout.cardWidth, height: height, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: NotchLayout.cardCorner, style: .circular))
    }

    private var tail: some View {
        let size = TooltipTail.size(for: direction)
        // Deliberately outside the clip: the tail is part of the card's
        // silhouette, not of its contents. Pulled back half a point into the
        // card so the two fills overlap — abutted exactly, antialiasing leaves
        // a hairline of background showing along the join.
        return TooltipTail(direction: direction)
            .fill(Palette.card)
            .frame(width: size.width, height: size.height)
            .padding(overlapEdge, -0.5)
    }

    /// Which side of the tail touches the card.
    private var overlapEdge: Edge.Set {
        switch direction {
        case .leading:  return .leading
        case .trailing: return .trailing
        case .down:     return .bottom
        case .up:       return .top
        }
    }

    var body: some View {
        // Card first or tail first, laid out along whichever axis the tail
        // points. The pair is one silhouette either way.
        switch direction {
        case .leading:  HStack(spacing: 0) { card; tail }
        case .trailing: HStack(spacing: 0) { tail; card }
        case .down:     VStack(spacing: 0) { tail; card }
        case .up:       VStack(spacing: 0) { card; tail }
        }
    }
}

/// A label on the left, its figure on the right, and — where the row is a share
/// of something — a bar underneath saying so.
private struct MetricRowView: View {
    let row: MetricRow

    private var trackWidth: CGFloat { NotchLayout.cardTextWidth }

    private var fillWidth: CGFloat {
        let fraction = CGFloat(min(max(row.fraction ?? 0, 0), 1))
        // Never thinner than it is tall, so a 0.2% share is still a mark rather
        // than a hairline that reads as nothing at all.
        return max(NotchLayout.barHeight, trackWidth * fraction)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Design.px(20)) {
                Text(row.label)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                Text(row.value)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            .font(Typography.cardBody)

            if row.fraction != nil {
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.barTrack)
                    Capsule().fill(row.tint ?? Palette.textSecondary).frame(width: fillWidth)
                    if let marker = row.marker {
                        // Break-even. Drawn over the fill and in the card's own
                        // black, so it reads as a notch cut into the bar rather
                        // than as another value plotted on it.
                        Capsule()
                            .fill(Palette.card)
                            .frame(width: NotchLayout.markerWidth)
                            .offset(x: trackWidth * CGFloat(min(max(marker, 0), 1))
                                    - NotchLayout.markerWidth / 2)
                    }
                }
                .frame(width: trackWidth, height: NotchLayout.barHeight)
                .padding(.top, NotchLayout.labelToBar)
            }
        }
    }
}

struct TooltipCard: View {
    let ring: RingSnapshot
    /// Which way the card sits from the notch, which follows from the edge.
    var direction: NotchEdge.TooltipDirection = .leading

    /// The same figure the hover region and the panel budget use.
    private var height: CGFloat { ring.cardHeight }

    var body: some View {
        TooltipShell(height: height, direction: direction) {
            VStack(alignment: .leading, spacing: 0) {
                // Who this is about, and over what stretch — small, because it
                // is context rather than content.
                HStack(spacing: NotchLayout.headerGap) {
                    RingGlyphView(glyph: ring.glyph)
                        .foregroundStyle(Palette.textPrimary)
                    Text(ring.title)
                        .font(Typography.cardTitle)
                        .foregroundStyle(Palette.textPrimary)
                    Spacer(minLength: Design.px(20))
                    Text(ring.caption)
                        .font(Typography.cardBody)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                }

                if let note = ring.note {
                    Text(note)
                        .font(Typography.cardBody)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, NotchLayout.headerToBlock)
                } else {
                    hero
                    ForEach(Array(ring.rows.enumerated()), id: \.element.id) { index, row in
                        if row.startsGroup, index > 0 {
                            Rectangle()
                                .fill(Palette.cardRule)
                                .frame(height: NotchLayout.hairline)
                                .padding(.top, NotchLayout.groupSpacing)
                        }
                        MetricRowView(row: row)
                            .padding(.top, index == 0 ? NotchLayout.headerToBlock
                                     : (row.startsGroup ? NotchLayout.groupSpacing
                                                        : NotchLayout.rowSpacing))
                    }
                }
            }
            // Contents swap wholesale between rings rather than interpolating
            // from one ring's numbers into another's.
            .id(ring.id)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    /// The answer, at the size an answer deserves.
    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(ring.hero)
                .font(Typography.hero)
                .foregroundStyle(ring.heroTint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
                .animation(NotchMotion.reading, value: ring.hero)
                .padding(.top, NotchLayout.heroGap)

            Text(ring.heroCaption)
                .font(Typography.heroCaption)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.top, NotchLayout.heroCaptionGap)

            if let fraction = ring.heroFraction {
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.barTrack)
                    Capsule()
                        .fill(ring.heroTint)
                        .frame(width: max(NotchLayout.heroBarHeight,
                                          NotchLayout.cardTextWidth * CGFloat(min(max(fraction, 0), 1))))
                    if let marker = ring.heroMarker {
                        // Break-even, cut into the bar in the card's own black.
                        Capsule()
                            .fill(Palette.card)
                            .frame(width: NotchLayout.markerWidth)
                            .offset(x: NotchLayout.cardTextWidth * CGFloat(min(max(marker, 0), 1))
                                    - NotchLayout.markerWidth / 2)
                    }
                }
                .frame(width: NotchLayout.cardTextWidth, height: NotchLayout.heroBarHeight)
                .padding(.top, NotchLayout.heroBarGap)
            }
        }
    }
}
