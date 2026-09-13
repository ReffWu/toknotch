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
                            .frame(width: 48, height: 48)
                            .padding(3)
                            .overlay(
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2.5)
                            )
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
