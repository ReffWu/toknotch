import Foundation

/// Which screen edge the notch is welded to.
///
/// The edge decides two things that ripple through the whole surface: which way
/// the provider stack runs, and which way the tooltip leaves. A side edge keeps
/// the original vertical column. Top and bottom turn the stack on its side —
/// four cells stacked vertically make the notch 401pt long, and hanging that off
/// the menu bar would reach a quarter of the way down the screen.
enum NotchEdge: String, CaseIterable, Identifiable {
    case right
    case left
    case top
    case bottom

    var id: String { rawValue }

    /// True when the stack runs down the screen rather than across it.
    var isVertical: Bool { self == .right || self == .left }

    /// Where the tooltip goes: away from the bezel, always.
    enum TooltipDirection: Equatable {
        case leading    // card to the left of the notch
        case trailing   // card to the right of it
        case up         // card above it
        case down       // card below it
    }

    var tooltipDirection: TooltipDirection {
        switch self {
        case .right:  return .leading
        case .left:   return .trailing
        case .top:    return .down
        case .bottom: return .up
        }
    }

    /// A unit vector pointing at the bezel, in panel coordinates (y grows down,
    /// as it does in a flipped `NSHostingView` and in SwiftUI). This is the way
    /// the contents slide as the notch folds away into the edge.
    var outward: CGPoint {
        switch self {
        case .right:  return CGPoint(x: 1, y: 0)
        case .left:   return CGPoint(x: -1, y: 0)
        case .top:    return CGPoint(x: 0, y: -1)
        case .bottom: return CGPoint(x: 0, y: 1)
        }
    }

    /// A unit vector along the stack, in the same panel coordinates as
    /// `outward`. Perpendicular to it by construction: the stack runs *along*
    /// the bezel, and `across` leaves the bezel at a right angle.
    var alongDirection: CGPoint {
        isVertical ? CGPoint(x: 0, y: 1) : CGPoint(x: 1, y: 0)
    }

    var title: String {
        switch self {
        case .right:  return "Right"
        case .left:   return "Left"
        case .top:    return "Top"
        case .bottom: return "Bottom"
        }
    }

    var explanation: String {
        switch self {
        case .right:
            return "Down the right-hand edge, clear of a Dock on that side."
        case .left:
            return "Down the left-hand edge, clear of a Dock on that side."
        case .top:
            return "A wide bar across the top, readings side by side. On a Mac "
                 + "with a notch of its own it runs up to meet it, so the two "
                 + "read as one shape."
        case .bottom:
            return "A wide bar resting on top of the Dock, readings side by side."
        }
    }
}
