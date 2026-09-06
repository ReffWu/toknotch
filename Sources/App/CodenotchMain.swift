import SwiftUI

@main
struct CodenotchMain: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The notch is the UI; the panel is put up by the delegate. This scene
        // exists only because `App` needs one.
        Settings { EmptyView() }
    }
}
