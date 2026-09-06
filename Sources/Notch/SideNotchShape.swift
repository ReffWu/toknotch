import SwiftUI

/// The notch body: a pill welded to one edge of the screen, with *inverse*
/// rounded corners at each end that flare back out to the edge so it reads as
/// part of the bezel rather than a floating panel.
///
/// The path is only ever written once, for the right edge, and then transformed
/// onto whichever edge it is actually on. Writing four variants would mean four
/// copies of the corner-versus-flare clamping below, which is the one piece of
/// this that took real work to get right — and three of the copies would never
/// be the one under the cursor when it broke.
///
/// In canonical form `rect` is the whole shape including the flares; the
/// straight body runs from `rect.minY + curlRadius` to `rect.maxY - curlRadius`,
/// and `rect.maxX` is the screen edge.
struct SideNotchShape: Shape {
    var edge: NotchEdge = .right
    /// The display's own notch, when this one is drawn as it.
    ///
    /// Set for a top edge on a Mac that has one, and it changes two things.
    /// The flares go: they are what make this shape read as *growing out of* an
    /// edge, and the hardware notch does not taper — it is a straight-sided
    /// black rectangle hanging from the top with two rounded bottom corners.
    /// And the corner is capped at half the hardware's own height, so it is the
    /// same size at rest as it is open: left to the frame it is clamped to half
    /// the *current* depth, which makes the resting shape very nearly a pill
    /// and turns opening it into a rounded tab morphing into a bar rather than
    /// the notch stretching.
    var joining: HardwareNotch?
    var curlRadius: CGFloat = NotchLayout.curlRadius
    var cornerRadius: CGFloat = NotchLayout.cornerRadius

    func path(in rect: CGRect) -> Path {
        // Canonical space: depth across the shape, length along it. For a side
        // edge that is already width x height; for a horizontal one it is the
        // rect turned on its side. The bezel is at `maxX`.
        let depth = edge.isVertical ? rect.width : rect.height
        let length = edge.isVertical ? rect.height : rect.width
        let canonical = canonicalPath(
            in: CGRect(x: 0, y: 0, width: depth, height: length),
            flare: joining == nil ? curlRadius : NotchLayout.bezelFillet,
            // Half the hardware's height is the most the resting shape can
            // carry; holding it there keeps every frame of the expansion the
            // same shape, only bigger.
            cornerCap: joining.map { $0.height / 2 } ?? .greatestFiniteMagnitude
        )

        return canonical
            .applying(Self.transform(for: edge, depth: depth))
            .applying(CGAffineTransform(translationX: rect.minX, y: rect.minY))
    }

    /// Canonical (`u`, `v`) — `u` across from the far side, `v` along — onto the
    /// rect's own coordinates, with the bezel landing on the right edge.
    ///
    /// Derived rather than eyeballed: in stack space the bezel is always
    /// `across == 0`, so `across = depth - u`, and each edge then places
    /// `(along, across)` the same way `NotchPlacement` does.
    static func transform(for edge: NotchEdge, depth: CGFloat) -> CGAffineTransform {
        switch edge {
        case .right:
            return .identity
        case .left:
            // Mirrored: the flares point the other way.
            return CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: depth, ty: 0)
        case .top:
            // Quarter turn, bezel to the top.
            return CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: depth)
        case .bottom:
            // Quarter turn the other way, bezel to the bottom.
            return CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)
        }
    }

    private func canonicalPath(in rect: CGRect, flare: CGFloat,
                               cornerCap: CGFloat = .greatestFiniteMagnitude) -> Path {
        // Order matters. Clamping the corner by `width - curl` — the obvious
        // reading — collapses it to zero as soon as the flare is as wide as the
        // body, which is exactly what happens when the notch folds to its pill:
        // a 10pt-wide shape came out with square corners. The corner is claimed
        // first, out of half the width, and the flare takes what is left.
        let wanted = max(0, min(cornerRadius, cornerCap, rect.width / 2))
        let curl = max(0, min(flare, rect.height / 2, rect.width - wanted))
        let corner = max(0, min(wanted, (rect.height - 2 * curl) / 2))
        let bodyTop = rect.minY + curl
        let bodyBottom = rect.maxY - curl

        var path = Path()
        // Screen edge, above the body.
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        // Flare inward and down onto the top edge. Absent when flush: the
        // shape meets the bezel square, as the hardware notch does.
        if curl > 0 {
            path.addArc(
                center: CGPoint(x: rect.maxX - curl, y: rect.minY),
                radius: curl,
                startAngle: .degrees(0), endAngle: .degrees(90),
                clockwise: false
            )
        }
        path.addLine(to: CGPoint(x: rect.minX + corner, y: bodyTop))
        path.addArc(
            center: CGPoint(x: rect.minX + corner, y: bodyTop + corner),
            radius: corner,
            startAngle: .degrees(270), endAngle: .degrees(180),
            clockwise: true
        )
        path.addLine(to: CGPoint(x: rect.minX, y: bodyBottom - corner))
        path.addArc(
            center: CGPoint(x: rect.minX + corner, y: bodyBottom - corner),
            radius: corner,
            startAngle: .degrees(180), endAngle: .degrees(90),
            clockwise: true
        )
        path.addLine(to: CGPoint(x: rect.maxX - curl, y: bodyBottom))
        // Flare back out to the screen edge.
        if curl > 0 {
            path.addArc(
                center: CGPoint(x: rect.maxX - curl, y: rect.maxY),
                radius: curl,
                startAngle: .degrees(270), endAngle: .degrees(360),
                clockwise: false
            )
        }
        path.closeSubpath()
        return path
    }
}
