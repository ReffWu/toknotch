import SwiftUI

@main
struct TokNotchMain: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The notch is the UI; the panel is put up by the delegate. This scene
        // exists only because `App` needs one.
        Settings { EmptyView() }

        // Decided once at launch: an App's scenes are not rebuilt when the
        // delegate changes, so the panel itself watches for launch to finish.
        MenuBarExtra(isInserted: .constant(AppDelegate.hasMenuBarIcon)) {
            MenuBarRoot(app: appDelegate)
        } label: {
            // The menu bar mark is its own drawing, not the app icon shrunk
            // down, and a template image so macOS tints it for the bar it sits
            // on. Drawn for 1x and 2x by `Scripts/make-menu-bar-icon.py`.
            Image("MenuBarIcon")
                .accessibilityLabel(Text(verbatim: "TokNotch"))
        }
        .menuBarExtraStyle(.window)
    }
}

/// Waits for the delegate to have built what the panel reads.
private struct MenuBarRoot: View {
    @ObservedObject var app: AppDelegate

    var body: some View {
        if let context = app.menuBar {
            MenuBarPanel(preferences: context.preferences, store: context.store,
                         updater: context.updater,
                         onOpenSettings: context.openSettings, onAbout: context.about)
        }
    }
}
