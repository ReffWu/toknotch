import AppKit

/// Where TokNotch shows itself, apart from the notch.
///
/// The notch is the product; this is only about how the *app* is reached — to
/// open settings, or to quit it. Three states because the two obvious ones
/// leave a gap: a Dock tile is easy to find and permanent, a menu bar item is
/// out of the way but still there, and some people want neither.
enum AppPresence: String, CaseIterable, Identifiable {
    /// A normal app: Dock tile, ⌘-Tab entry, menu bar of its own.
    case dock
    /// An icon in the menu bar, and nothing in the Dock.
    case menuBar
    /// Neither. Only the notch itself.
    case hidden

    var id: String { rawValue }

    /// The name shown on the control, in the reader's language.
    func title(_ language: AppLanguage) -> String {
        switch self {
        case .dock: return language.t("appPresence.dock.title")
        case .menuBar: return language.t("appPresence.menuBar.title")
        case .hidden: return language.t("appPresence.hidden.title")
        }
    }

    /// The line under it that says what choosing this actually does.
    func explanation(_ language: AppLanguage) -> String {
        switch self {
        case .dock: return language.t("appPresence.dock.explanation")
        case .menuBar: return language.t("appPresence.menuBar.explanation")
        case .hidden: return language.t("appPresence.hidden.explanation")
        }
    }

    /// Whether the app claims a Dock tile. `.accessory` is what keeps a
    /// menu-bar-only or invisible copy out of the Dock and the app switcher.
    var activationPolicy: NSApplication.ActivationPolicy {
        self == .dock ? .regular : .accessory
    }

    var wantsStatusItem: Bool { self == .menuBar }
}
