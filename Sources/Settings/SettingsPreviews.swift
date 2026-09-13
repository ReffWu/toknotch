import SwiftUI

/// The little pictures on the Settings page.
///
/// Both settings there are about *where a thing sits on your screen*, which is
/// the one kind of choice a word cannot make obvious — "屏幕右侧" and "顶部刘海"
/// are equally short and equally unhelpful until you see them. So each option
/// draws a tiny screen with the notch on it, the way System Settings draws a
/// tiny window for Light and Dark.
struct ScreenPreview<Content: View>: View {
    @ViewBuilder let notch: Content

    var body: some View {
        ZStack {
            // Light, not the desktop-blue it was: the mark drawn on top is
            // black, and a dark screen left it nearly invisible — exactly the
            // "看不清" a picture is supposed to fix, not cause.
            LinearGradient(colors: [Color(hex: 0xEDEFF3), Color(hex: 0xD6DAE2)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            // The menu bar, so "top" reads as the top of a Mac rather than the
            // top of a rectangle.
            VStack(spacing: 0) {
                Rectangle().fill(.black.opacity(0.16)).frame(height: 3.5)
                Spacer(minLength: 0)
            }
            notch
        }
    }
}

/// Where the notch is welded.
struct NotchEdgePreview: View {
    let edge: NotchEdge

    var body: some View {
        ScreenPreview {
            GeometryReader { proxy in
                let long = min(proxy.size.height, proxy.size.width) * 0.52
                let thick: CGFloat = 7
                let size = edge.isVertical
                    ? CGSize(width: thick, height: long)
                    : CGSize(width: long, height: thick)
                // The real shape, not a stand-in: a plain rounded rectangle
                // reads as a floating pill, but the notch is welded to the
                // bezel — flared flush into the edge on that side, rounded
                // only on the far one. Small numbers scaled for this tiny
                // canvas rather than the app's own — the real ones are sized
                // for a 30-40pt notch, not a 7pt one.
                SideNotchShape(edge: edge, curlRadius: 3, cornerRadius: 2.5)
                    .fill(.black)
                    .frame(width: size.width, height: size.height)
                    .position(centre(in: proxy.size, size: size))
            }
        }
    }

    private func centre(in bounds: CGSize, size: CGSize) -> CGPoint {
        switch edge {
        case .right:  return CGPoint(x: bounds.width - size.width / 2, y: bounds.height / 2)
        case .left:   return CGPoint(x: size.width / 2, y: bounds.height / 2)
        case .top:    return CGPoint(x: bounds.width / 2, y: size.height / 2)
        case .bottom: return CGPoint(x: bounds.width / 2, y: bounds.height - size.height / 2)
        }
    }
}

/// How much of itself the notch shows at rest.
struct NotchVisibilityPreview: View {
    let visibility: NotchVisibility
    /// Drawn on the edge the notch is actually on, so the two pictures above
    /// and below each other describe the same notch.
    let edge: NotchEdge

    var body: some View {
        ScreenPreview {
            GeometryReader { proxy in
                // Folding away shrinks the notch's *depth*, not its length —
                // the collapsed pill stands nearly as long as the open shape,
                // just a sliver of how far it reaches off the edge.
                let thick = visibility == .alwaysShow ? Self.openThick : Self.restingThick
                let long = min(proxy.size.height, proxy.size.width) * 0.52
                let size = edge.isVertical
                    ? CGSize(width: thick, height: long)
                    : CGSize(width: long, height: thick)
                SideNotchShape(edge: edge, curlRadius: min(3, thick / 2),
                               cornerRadius: min(2.5, thick / 2))
                    .fill(.black)
                    .frame(width: size.width, height: size.height)
                    .position(centre(in: proxy.size, size: size))
            }
        }
    }

    private static let openThick: CGFloat = 7
    /// The real pill is about a sixth of the open notch's depth
    /// (`NotchLayout.pillWidth` against `sideBodyDepth`); a sixth of 7pt reads
    /// as a hairline at this size, so this is eased up for legibility rather
    /// than drawn to the literal ratio.
    private static let restingThick: CGFloat = 3

    private func centre(in bounds: CGSize, size: CGSize) -> CGPoint {
        switch edge {
        case .right:  return CGPoint(x: bounds.width - size.width / 2, y: bounds.height / 2)
        case .left:   return CGPoint(x: size.width / 2, y: bounds.height / 2)
        case .top:    return CGPoint(x: bounds.width / 2, y: size.height / 2)
        case .bottom: return CGPoint(x: bounds.width / 2, y: bounds.height - size.height / 2)
        }
    }
}
