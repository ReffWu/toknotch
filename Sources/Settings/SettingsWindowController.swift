import AppKit
import SwiftUI

/// Hosts the settings sheet in its own window.
///
/// A real window rather than a panel attached to the notch: settings are a place
/// you go, not something you glance at, and a floating panel that follows the
/// notch would be one more thing hovering over the screen edge.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let preferences: Preferences
    /// The live store, so the vendor list and the source status stay current
    /// while the window is open rather than being snapshotted when it opens.
    private let store: UsageStore
    private let updater: Updater

    init(preferences: Preferences, store: UsageStore, updater: Updater) {
        self.preferences = preferences
        self.store = store
        self.updater = updater
    }

    /// Bring the window to the front from an accessory app.
    ///
    /// `makeKeyAndOrderFront` plus `activate` is not enough on its own here:
    /// an app with no dock icon is not always allowed to pull itself in front
    /// of whatever the user is working in, and the window then opens silently
    /// behind everything. `orderFrontRegardless` is the part that does not ask
    /// permission, and it is why the window appears at all.
    private func surface(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func show() {
        if let window {
            surface(window)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0,
                                width: SettingsView.width, height: SettingsView.height),
            // No `fullSizeContentView`: it pulls content up beneath the title
            // bar, and the form's first section header would sit behind it.
            // `fullSizeContentView`: the sidebar and the content run all the way
            // to the top of the window. There is nothing a title bar would carry
            // here — the sidebar already says which page you are on, and the
            // split view's own toggle only offers to hide the one control that
            // makes the window navigable.
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "TokNotch"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.contentView = NSHostingView(
            rootView: SettingsView(preferences: preferences, store: store, updater: updater)
        )
        window.center()
        window.isReleasedWhenClosed = false
        self.window = window
        surface(window)
    }
}
