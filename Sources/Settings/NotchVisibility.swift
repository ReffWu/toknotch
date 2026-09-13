import Foundation

/// How much of itself the notch shows when you are not using it.
///
/// No "hidden": the notch is the product, and a TokNotch with nothing on screen
/// is indistinguishable from one that failed to start. At rest it is already a
/// small pill that opens on contact, which is as quiet as it needs to get.
enum NotchVisibility: String, CaseIterable, Identifiable {
    /// Pinned open. The readings are always on screen.
    case alwaysShow
    /// A pill at the edge that unfolds when the pointer reaches it. The default.
    case onHover

    var id: String { rawValue }

    /// The name shown on the control, in the reader's language.
    func title(_ language: AppLanguage) -> String {
        switch self {
        case .alwaysShow: return language.t("notchVisibility.alwaysShow.title")
        case .onHover: return language.t("notchVisibility.onHover.title")
        }
    }

    /// The line under it that says what choosing this actually does.
    func explanation(_ language: AppLanguage) -> String {
        switch self {
        case .alwaysShow: return language.t("notchVisibility.alwaysShow.explanation")
        case .onHover: return language.t("notchVisibility.onHover.explanation")
        }
    }
}
