import SwiftUI

/// The little pictures on the Appearance page.
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

    var body: some View {
        ScreenPreview {
            GeometryReader { proxy in
                let full = proxy.size.height * 0.52
                switch visibility {
                case .alwaysShow:
                    bar(height: full, in: proxy.size)
                case .onHover:
                    // The resting pill: the same object, most of it folded away.
                    bar(height: full * 0.42, in: proxy.size)
                case .hidden:
                    // Not simply blank: a blank box looks identical whether or
                    // not the click landed, and gave no way to tell the option
                    // had actually been picked. An outline of where the pill
                    // would sit, with nothing filling it, reads as "gone" while
                    // still confirming a choice was drawn.
                    outline(height: full * 0.42, in: proxy.size)
                }
            }
        }
    }

    /// This preview is always the right edge, whatever "貼在哪条边" is set to
    /// — it is showing how *much* shows, not where, so one fixed edge is the
    /// right constant to hold.
    private static let thick: CGFloat = 7

    private func bar(height: CGFloat, in bounds: CGSize) -> some View {
        SideNotchShape(edge: .right, curlRadius: 3, cornerRadius: 2.5)
            .fill(.black)
            .frame(width: Self.thick, height: height)
            .position(x: bounds.width - Self.thick / 2, y: bounds.height / 2)
    }

    private func outline(height: CGFloat, in bounds: CGSize) -> some View {
        SideNotchShape(edge: .right, curlRadius: 3, cornerRadius: 2.5)
            .stroke(Color.black.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            .frame(width: Self.thick, height: height)
            .position(x: bounds.width - Self.thick / 2, y: bounds.height / 2)
    }
}
