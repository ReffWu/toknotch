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

    var title: String {
        switch self {
        case .dock:    return "Dock"
        case .menuBar: return "Menu bar"
        case .hidden:  return "Neither"
        }
    }

    var chineseTitle: String {
        switch self {
        case .dock:    return "仅 Dock 栏"
        case .menuBar: return "仅菜单栏"
        case .hidden:  return "无图标"
        }
    }

    var explanation: String {
        switch self {
        case .dock:
            return "A normal app icon in the Dock while TokNotch is running."
        case .menuBar:
            return "A small icon in the menu bar instead, and nothing in the Dock."
        case .hidden:
            // Said here because choosing this removes every visible way back to
            // these settings, and finding that out afterwards is too late.
            return "No icon anywhere. Open TokNotch again from Applications to "
                 + "bring these settings back."
        }
    }

    var chineseExplanation: String {
        switch self {
        case .dock:
            return "在程序坞（Dock）显示标准应用图标。"
        case .menuBar:
            return "仅在顶部菜单栏显示状态图标，不在 Dock 占用空间。"
        case .hidden:
            return "不在任何地方显示图标，仅保留刘海。可在应用程序中再次打开唤出设置。"
        }
    }

    /// `.regular` is the only one that gets a Dock tile. Both others are
    /// accessory apps; what separates them is whether a status item is made.
    var activationPolicy: NSApplication.ActivationPolicy {
        self == .dock ? .regular : .accessory
    }

    var wantsStatusItem: Bool { self == .menuBar }
}
