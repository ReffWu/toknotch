import AppKit
import SwiftUI

/// The frame around the app icon: the dark one the app ships with, or a light one.
///
/// Applied to the running Dock tile and to the bundle itself, so Finder and
/// Launchpad show the same choice. Writing the icon into the bundle keeps the
/// Developer ID signature valid for Gatekeeper; only a strict `codesign`
/// check notices the added Finder info.
enum AppIconStyle: String, CaseIterable, Identifiable {
    case dark
    case light

    var id: String { rawValue }

    private static let key = "appIconStyle"

    static var current: AppIconStyle {
        AppIconStyle(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .dark
    }

    var image: NSImage? { NSImage(named: "AppIcon-\(rawValue)") }

    static func choose(_ style: AppIconStyle) {
        UserDefaults.standard.set(style.rawValue, forKey: key)
        apply(style)
    }

    /// Re-applied at launch, because an update replaces the bundle and with it
    /// the custom icon written into it.
    static func restore() {
        if current != .dark { apply(current) }
    }

    private static func apply(_ style: AppIconStyle) {
        let image = style == .dark ? nil : style.image
        NSApp.applicationIconImage = image
        NSWorkspace.shared.setIcon(image, forFile: Bundle.main.bundlePath, options: [])
    }
}

/// The two icons side by side, the chosen one ringed.
struct AppIconPicker: View {
    let language: AppLanguage
    @State private var selection = AppIconStyle.current

    /// How large the icon's frame is drawn.
    private static let size: CGFloat = 46
    /// Where that frame sits in the artwork, from `Scripts/make-app-icon.py`:
    /// the opaque shape spans 980 of the image's 1024 pixels with 262-pixel
    /// circular corners, and the margin around it is drop shadow. Measured so
    /// the ring can follow the frame itself rather than the image's bounds.
    private static let drawn: CGFloat = size * 1024 / 980
    private static let corner: CGFloat = size * 262 / 980

    var body: some View {
        HStack(spacing: 10) {
            ForEach(AppIconStyle.allCases) { style in
                let selected = selection == style
                Button {
                    selection = style
                    AppIconStyle.choose(style)
                } label: {
                    VStack(spacing: 4) {
                        Image(nsImage: style.image ?? NSImage())
                            .resizable()
                            .frame(width: Self.drawn, height: Self.drawn)
                            .frame(width: Self.size, height: Self.size)
                            // The artwork's shadow is cut away: under a ring it
                            // only muddies the gap. The hairline keeps the light
                            // frame from dissolving into a white card.
                            .clipShape(RoundedRectangle(cornerRadius: Self.corner, style: .circular))
                            .overlay(
                                RoundedRectangle(cornerRadius: Self.corner, style: .circular)
                                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                            )
                            .selectionRing(selected, cornerRadius: Self.corner, style: .circular)
                        Text(language.t(style == .dark ? "settings.dark" : "settings.light"))
                            .font(.system(size: 11, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? .primary : .secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}
