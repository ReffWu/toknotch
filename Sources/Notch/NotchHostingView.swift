import AppKit
import SwiftUI

/// The panel's content view: it holds the hosting view and nothing else.
///
/// It exists so that SwiftUI is *not* the content view. As the content view an
/// `NSHostingView` reports the SwiftUI content's ideal size to the window, and
/// this notch's root is a `GeometryReader` whose ideal size is 10x10 — which on
/// a wide, shallow panel had AppKit walking the window down to zero height and
/// then throwing in the constraint pass. The panel's size is `NotchGeometry`'s
/// to decide, and a container is what makes that true.
///
/// It answers `hitTest` with whatever its subview says and never with itself.
/// A plain `NSView` would claim every point inside its bounds — and most of
/// this panel is empty space reserved for the tooltip, so that would turn the
/// hole the notch depends on into a wall.
final class NotchContainerView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        // `point` arrives in the superview's coordinates, and a subview's own
        // `hitTest` expects it in ours.
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        for subview in subviews.reversed() {
            if let hit = subview.hitTest(local) { return hit }
        }
        return nil
    }
}

/// The panel is much larger than the notch — it reserves room for the tooltip —
/// so everything outside the currently visible chrome has to pass clicks
/// through to whatever is underneath.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    /// Whether a point, in view coordinates, is on something that takes events.
    /// NSHostingView is flipped, so the point has a top-left origin.
    ///
    /// A question rather than a list of rects, because the honest answer is not
    /// a union of boxes: the settings handle is two circles, and the bounding
    /// box of the notch and the handle together took in a band the width of
    /// the whole notch where nothing is drawn at all.
    var isInteractive: (CGPoint) -> Bool = { _ in false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard isInteractive(local) else { return nil }
        return super.hitTest(point)
    }

    /// `NSView.menu` is not inherited by subviews, and the hit test lands on one
    /// of SwiftUI's, so AppKit would otherwise ask a view that has no menu.
    override func menu(for event: NSEvent) -> NSMenu? {
        let local = convert(event.locationInWindow, from: nil)
        guard isInteractive(local) else { return nil }
        return menu
    }
}
