import SwiftUI

/// The ring around a glyph: a grey track with a coloured arc that starts at
/// twelve o'clock and sweeps clockwise by the fraction the ring measures.
///
/// What that fraction *is* differs per ring and is never assumed here — the
/// snapshot arrives with it already worked out, and the card says out loud what
/// it was measured against. A ring with no honest denominator arrives with a
/// nil fraction and draws its track alone, which is the truthful shape for
/// "nothing to compare this to yet".
struct UsageRing: View {
    let fraction: Double?
    let glyph: RingGlyph
    let tint: Color
    /// A read in flight. The reading itself turns, rather than a second
    /// spinner appearing beside it: the thing being refetched should be the
    /// thing that moves.
    var isRefreshing: Bool = false
    /// Nothing to show — no data yet, or the read failed. Dims the mark.
    var isDormant: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin: Double = 0

    /// Past a full circle the arc simply closes. Beating your own best is said
    /// by the colour instead — a second lap on the same track reads as a bug
    /// long before it reads as an achievement.
    private var sweep: CGFloat { CGFloat(min(max(fraction ?? 0, 0), 1)) }

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Palette.ringTrack, lineWidth: NotchLayout.trackStroke)

            if fraction != nil {
                Circle()
                    .inset(by: NotchLayout.trackStroke / 2)
                    .trim(from: 0, to: sweep)
                    .stroke(tint, style: StrokeStyle(lineWidth: NotchLayout.progressStroke,
                                                     lineCap: .round))
                    .rotationEffect(.degrees(-90 + spin))
                    // A ring that snaps to a new value reads as a glitch; one
                    // that sweeps reads as a measurement being taken.
                    .animation(NotchMotion.reading, value: sweep)
                    .animation(NotchMotion.reading, value: tint)
            }

            RingGlyphView(glyph: glyph)
                .foregroundStyle(Palette.textPrimary)
                .opacity(isDormant ? 0.35 : 1)
        }
        .frame(width: NotchLayout.ringDiameter, height: NotchLayout.ringDiameter)
        // Pressed in while it works, released when the answer lands.
        .scaleEffect(isRefreshing ? 0.95 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.62), value: isRefreshing)
        .onChange(of: isRefreshing) { _, refreshing in
            guard refreshing, !reduceMotion else { return }
            // Exactly one turn, and it stops by itself.
            //
            // The obvious spelling — a `repeatForever` spin started on the way
            // in and cancelled on the way out — does not stop when you set the
            // value back: if the value you set is the one it is already
            // animating toward, nothing changes and it simply keeps going. A
            // single finite turn has no cancellation problem at all, since 360°
            // is the same angle as 0°, so it lands exactly where the reading
            // belongs.
            withAnimation(.timingCurve(0.32, 0, 0.14, 1, duration: 0.95)) {
                spin += 360
            }
        }
    }
}

/// A ring and the figure it stands for.
struct RingCell: View {
    let ring: RingSnapshot
    var isRefreshing: Bool = false

    var body: some View {
        VStack(spacing: NotchLayout.ringLabelGap) {
            UsageRing(fraction: ring.fraction, glyph: ring.glyph, tint: ring.tint,
                      isRefreshing: isRefreshing, isDormant: !ring.hasReading)
            Text(ring.headline)
                .font(Typography.percent)
                .foregroundStyle(Palette.textPrimary)
                // Never squeezed: across a horizontal edge the cell is only as
                // wide as the ring, and a label wider than that would be
                // truncated rather than allowed to overhang into the spacing
                // that is already there for it.
                .fixedSize(horizontal: true, vertical: false)
                .frame(height: NotchLayout.percentLineHeight)
                .contentTransition(.numericText())
                .animation(NotchMotion.reading, value: ring.headline)
        }
        .frame(height: NotchLayout.cellExtent)
    }
}
