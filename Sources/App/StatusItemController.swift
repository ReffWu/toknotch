import AppKit

/// The menu bar icon, present only while `AppPresence.menuBar` is chosen.
///
/// It exists to be a way *into* the app, so it opens settings and offers Quit —
/// with no Dock tile there is otherwise nothing to right-click, and an app you
/// cannot quit is a worse problem than one you cannot see.
@MainActor
final class StatusItemController {
    private var item: NSStatusItem?
    private let onOpenSettings: () -> Void

    init(onOpenSettings: @escaping () -> Void) {
        self.onOpenSettings = onOpenSettings
    }

    var isShowing: Bool { item != nil }

    func show() {
        guard item == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Self.icon()
        item.button?.toolTip = "Codenotch"

        let menu = NSMenu()
        menu.addItem(
            withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ","
        ).target = self
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit Codenotch", action: #selector(quit), keyEquivalent: "q"
        ).target = self
        item.menu = menu

        self.item = item
    }

    func hide() {
        guard let item else { return }
        NSStatusBar.system.removeStatusItem(item)
        self.item = nil
    }

    /// The menu bar mark: its own drawing, not the app icon shrunk down.
    ///
    /// A template image, which is what lets macOS tint it — dark on a light
    /// menu bar, light on a dark one, and correct against a wallpaper-tinted
    /// bar without the app knowing any of that. The full-colour app icon can do
    /// none of it: it would fight every system item beside it and ignore the
    /// user's appearance entirely.
    ///
    /// Vector, so it is drawn at whatever the bar asks for rather than scaled
    /// from a fixed bitmap.
    static func icon() -> NSImage? {
        guard let image = NSImage(named: "MenuBarIcon") else { return nil }
        // Menu bar items are laid out on an 18pt square; taller and macOS
        // clips it, shorter and it floats.
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }

    @objc private func openSettings() { onOpenSettings() }
    @objc private func quit() { NSApp.terminate(nil) }
}
