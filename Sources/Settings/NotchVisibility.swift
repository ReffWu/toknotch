import Foundation

/// How much of itself the notch shows when you are not using it.
///
/// Three states rather than the two that get asked for, because the default is
/// neither: at rest the notch is already a small pill that opens on contact.
/// Offering only "always" and "hidden" would quietly delete the behaviour the
/// app was designed around.
enum NotchVisibility: String, CaseIterable, Identifiable {
    /// Pinned open. The readings are always on screen.
    case alwaysShow
    /// A pill at the edge that unfolds when the pointer reaches it. The default.
    case onHover
    /// Nothing on screen at all.
    case hidden

    var id: String { rawValue }

    var title: String {
        switch self {
        case .alwaysShow: return "Always show"
        case .onHover:    return "Show on hover"
        case .hidden:     return "Hide"
        }
    }

    var chineseTitle: String {
        switch self {
        case .alwaysShow: return "始终展开"
        case .onHover:    return "悬停展开"
        case .hidden:     return "完全隐藏"
        }
    }

    var explanation: String {
        switch self {
        case .alwaysShow:
            return "The notch stays open with every reading visible."
        case .onHover:
            return "A small pill at the screen edge that opens when you reach it."
        case .hidden:
            // Said here because a hidden notch is also a hidden way back in.
            return "Nothing on screen. Open TokNotch again from Applications "
                 + "to bring these settings back."
        }
    }

    var chineseExplanation: String {
        switch self {
        case .alwaysShow:
            return "刘海常驻展开，所有指标环始终在屏幕顶部可见。"
        case .onHover:
            return "屏幕顶部纯黑精致小胶囊，鼠标悬停时平滑物理展开。"
        case .hidden:
            return "屏幕上不显示任何元素。可在应用程序中重新打开 TokNotch 唤出设置。"
        }
    }
}
