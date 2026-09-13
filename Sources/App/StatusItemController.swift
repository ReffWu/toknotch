import AppKit

/// The menu bar icon, always there.
///
/// TokNotch keeps no Dock tile, so this is the way into the app: a glance at
/// the numbers, settings, updates and Quit. An app you cannot find or quit is
/// a worse problem than one more icon in the menu bar.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private var item: NSStatusItem?
    private let preferences: Preferences
    private let store: UsageStore
    private let updater: Updater
    private let onOpenSettings: () -> Void
    private let onAbout: () -> Void

    private var language: AppLanguage { preferences.appLanguage }

    init(preferences: Preferences, store: UsageStore, updater: Updater,
         onOpenSettings: @escaping () -> Void, onAbout: @escaping () -> Void) {
        self.preferences = preferences
        self.store = store
        self.updater = updater
        self.onOpenSettings = onOpenSettings
        self.onAbout = onAbout
    }

    func show() {
        guard item == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Self.icon()
        item.button?.toolTip = "TokNotch"
        item.button?.setAccessibilityLabel("TokNotch")

        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu

        self.item = item
    }

    /// Built as it opens, so the summary is current and every item is in the
    /// language chosen a moment ago.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if let summary = summary() {
            let line = NSMenuItem(title: summary, action: nil, keyEquivalent: "")
            line.isEnabled = false
            menu.addItem(line)
            menu.addItem(.separator())
        }

        menu.addItem(withTitle: language.t("menu.about"),
                     action: #selector(about), keyEquivalent: "").target = self
        menu.addItem(withTitle: language.t("menu.open"),
                     action: #selector(openSettings), keyEquivalent: ",").target = self
        if Updater.isConfigured {
            menu.addItem(withTitle: language.t("settings.checkForUpdates"),
                         action: #selector(checkForUpdates), keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: language.t("menu.quit"),
                     action: #selector(quit), keyEquivalent: "q").target = self
    }

    /// "13.4× paid back this period · Today 120M": the two numbers worth a
    /// glance, each only once there is something to say.
    private func summary() -> String? {
        var parts: [String] = []
        if let total = store.periodPayback(), total.paid > 0 {
            parts.append(language.t("menu.payback", String(format: "%.1f×", total.earned / total.paid)))
        }
        if let today = store.rings.first(where: { $0.kind == .today }), today.hasReading {
            parts.append("\(language.t("settings.today")) \(today.headline)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The menu bar mark: its own drawing, not the app icon shrunk down.
    ///
    /// A template image, which is what lets macOS tint it — dark on a light
    /// menu bar, light on a dark one, and correct against a wallpaper-tinted
    /// bar without the app knowing any of that. The full-colour app icon can do
    /// none of it: it would fight every system item beside it and ignore the
    /// user's appearance entirely.
    ///
    /// A MacBook screen with three rings in its notch, drawn separately for
    /// 1x and 2x by `Scripts/make-menu-bar-icon.py`: at 18 pixels a ring has
    /// no hole, so the 1x has square cut-outs on whole pixels instead.
    static func icon() -> NSImage? {
        guard let image = NSImage(named: "MenuBarIcon") else { return nil }
        // Menu bar items are laid out on an 18pt square; taller and macOS
        // clips it, shorter and it floats.
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }

    @objc private func openSettings() { onOpenSettings() }
    @objc private func about() { onAbout() }
    @objc private func checkForUpdates() { updater.checkForUpdates() }
    @objc private func quit() { NSApp.terminate(nil) }
}
