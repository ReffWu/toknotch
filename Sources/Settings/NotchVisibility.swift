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

    /// The name shown on the control, in the reader's language.
    func title(_ language: AppLanguage) -> String {
        switch self {
        case .alwaysShow: return language.t("notchVisibility.alwaysShow.title")
        case .onHover: return language.t("notchVisibility.onHover.title")
        case .hidden: return language.t("notchVisibility.hidden.title")
        }
    }

    /// The line under it that says what choosing this actually does.
    func explanation(_ language: AppLanguage) -> String {
        switch self {
        case .alwaysShow: return language.t("notchVisibility.alwaysShow.explanation")
        case .onHover: return language.t("notchVisibility.onHover.explanation")
        case .hidden: return language.t("notchVisibility.hidden.explanation")
        }
    }
}
