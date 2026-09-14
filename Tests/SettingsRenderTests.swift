import XCTest
import SwiftUI
@testable import TokNotch

/// Renders the settings window so it can actually be looked at.
///
/// Set `SETTINGS_RENDER_PATH` to a directory and each page is written there.
@MainActor
final class SettingsRenderTests: XCTestCase {
    private func makeStore() -> UsageStore {
        let store = UsageStore()
        store.loadForTesting(Fixtures.digest())
        return store
    }

    private func makePreferences() -> Preferences {
        let name = "SettingsRenderTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let preferences = Preferences(defaults: defaults)
        preferences.enabledVendors = [.anthropic]
        preferences.subscriptions = [
            .anthropic: Subscription(monthlyUSD: 200, renewalDay: 3),
            .openai: Subscription(monthlyUSD: 20, renewalDay: 17)
        ]
        return preferences
    }

    /// The pages are photographed on their own: `NavigationSplitView` needs a
    /// real window and comes back from `ImageRenderer` as a placeholder.
    func testEveryPageLaysOut() throws {
        let preferences = makePreferences()
        let store = makeStore()
        store.subscriptions = preferences.subscriptions
        store.enabledVendors = preferences.enabledVendors

        let pages: [(String, AnyView)] = [
            ("payback", AnyView(PaybackPage(preferences: preferences, store: store))),
            ("settings", AnyView(PreferencesPage(preferences: preferences, updater: Updater())))
        ]

        for (name, page) in pages {
            let sized = page.frame(width: SettingsView.width - SettingsView.sidebarWidth,
                                   height: SettingsView.height)
            let renderer = ImageRenderer(content: sized)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.nsImage, "\(name) failed to render")
            XCTAssertGreaterThan(image.size.height, 100, "\(name) collapsed")

            if let directory = ProcessInfo.processInfo.environment["SETTINGS_RENDER_PATH"] {
                let tiff = try XCTUnwrap(image.tiffRepresentation)
                let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?
                    .representation(using: .png, properties: [:]))
                try png.write(to: URL(fileURLWithPath: directory)
                    .appendingPathComponent("settings-\(name).png"))
            }
        }
    }

    /// The menu bar panel, in both appearances.
    func testMenuBarPanelLaysOut() throws {
        let preferences = makePreferences()
        let store = makeStore()
        store.subscriptions = preferences.subscriptions

        for scheme in [ColorScheme.light, .dark] {
            let panel = MenuBarPanel(preferences: preferences, store: store, updater: Updater(),
                                     onOpenSettings: {}, onAbout: {})
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, scheme)
            let renderer = ImageRenderer(content: panel)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.nsImage, "panel failed to render")
            XCTAssertGreaterThan(image.size.height, 200, "panel collapsed")

            if let directory = ProcessInfo.processInfo.environment["SETTINGS_RENDER_PATH"] {
                let tiff = try XCTUnwrap(image.tiffRepresentation)
                let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?
                    .representation(using: .png, properties: [:]))
                try png.write(to: URL(fileURLWithPath: directory)
                    .appendingPathComponent("menu-bar-panel-\(scheme == .dark ? "dark" : "light").png"))
            }
        }
    }
}
