import AppKit
import SwiftUI

/// Puts up the What's New dialogue, once per version.
///
/// Its own window rather than a sheet: there is nothing for a sheet to attach
/// to on a launch where no other window is open, which is every launch but the
/// first.
@MainActor
final class WhatsNewWindowController {
    /// Called after it has been dismissed, so the caller can decide what
    /// follows — on a first launch, the settings window does.
    var onDismiss: (() -> Void)?

    private var window: NSWindow?
    private let preferences: Preferences
    private let version: String

    init(preferences: Preferences, version: String) {
        self.preferences = preferences
        self.version = version
    }

    /// Show this version's changes, if it has any that have not been shown.
    ///
    /// A version with nothing written for it is still recorded as seen. Left
    /// unrecorded it would surface later — long after it was current — the
    /// first time a note happened to exist for it.
    ///
    /// Returns whether anything was put on screen, so the caller can sequence
    /// what comes next rather than racing it.
    @discardableResult
    func showIfNeeded() -> Bool {
        guard let note = ReleaseNotes.unseen(
            in: version, lastSeen: preferences.lastSeenVersion
        ) else {
            preferences.lastSeenVersion = version
            return false
        }
        show(note)
        return true
    }

    private func show(_ note: ReleaseNote) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0,
                                width: WhatsNewView.width, height: WhatsNewView.height),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "What's New"
        window.contentView = NSHostingView(
            rootView: WhatsNewView(note: note) { [weak self] in self?.dismiss() }
        )
        window.center()
        window.isReleasedWhenClosed = false
        // Closing it by the red button counts as having read it, the same as
        // pressing Continue — otherwise it would come back on the next launch.
        window.delegate = closeWatcher
        self.window = window

        // The same treatment the settings window needs: an app with no Dock
        // tile is not always allowed to come forward, and the window then opens
        // silently behind whatever the user was doing.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    /// Put it away, and count it as read.
    ///
    /// Idempotent, and it has to be: closing by the red button arrives here
    /// through `windowWillClose`, and this closes the window — so without the
    /// guard, and without dropping the delegate first, it called itself until
    /// the stack ran out.
    func dismiss() {
        guard let window else { return }
        self.window = nil

        // Recorded here rather than when the window opened: a crash in between
        // would otherwise swallow the one launch this was going to appear on.
        preferences.lastSeenVersion = version
        window.delegate = nil
        window.close()
        onDismiss?()
    }

    private lazy var closeWatcher = CloseWatcher { [weak self] in self?.dismiss() }
}

/// An `NSWindowDelegate` has to be an Objective-C class, which a `@MainActor`
/// Swift type holding closures cannot be directly.
private final class CloseWatcher: NSObject, NSWindowDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated { onClose() }
    }
}
