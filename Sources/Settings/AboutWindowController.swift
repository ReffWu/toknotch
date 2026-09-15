import AppKit
import SwiftUI

/// The About window: the one place the app icon is shown at a size where it
/// can actually be looked at.
///
/// Everywhere else the icon is 46pt or smaller, and the engraving that runs
/// along its frame is a grey hairline. TokNotch has no Dock tile either, so
/// without this nobody who installs it would ever see the icon properly.
@MainActor
final class AboutWindowController {
    private var window: NSWindow?
    private let preferences: Preferences
    private let version: String

    init(preferences: Preferences, version: String) {
        self.preferences = preferences
        self.version = version
    }

    func show() {
        // Rebuilt every time, so the frame chosen in Settings and the language
        // are whatever they are now, not what they were when it first opened.
        let view = AboutView(language: preferences.appLanguage, version: version)
        let hosting = NSHostingView(rootView: view)
        hosting.frame.size = hosting.fittingSize

        let window = self.window ?? {
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered, defer: false
            )
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
            return window
        }()
        window.title = preferences.appLanguage.t("menu.about")
        window.contentView = hosting
        window.setContentSize(hosting.fittingSize)

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}

struct AboutView: View {
    let language: AppLanguage
    let version: String

    private static let icon: CGFloat = 240

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    }

    var body: some View {
        VStack(spacing: 0) {
            // Clipped to the frame and given a shadow of its own: the one
            // baked into the artwork is cut off square at the image's edge,
            // which at this size shows as a faint box behind the icon. The
            // frame fills 980 of the artwork's 1024 pixels, with 262-pixel
            // circular corners.
            Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                .resizable()
                .interpolation(.high)
                .frame(width: Self.icon * 1024 / 980, height: Self.icon * 1024 / 980)
                .frame(width: Self.icon, height: Self.icon)
                .clipShape(RoundedRectangle(cornerRadius: Self.icon * 262 / 980, style: .circular))
                .shadow(color: .black.opacity(0.22), radius: 16, y: 8)
                .padding(.top, 40)
                .padding(.bottom, 6)
                .accessibilityHidden(true)

            Text(verbatim: "TokNotch")
                .font(.system(size: 24, weight: .semibold))
                .padding(.top, 8)

            Text(language.t("about.tagline"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 36)
                .padding(.top, 6)

            HStack(spacing: 6) {
                Text(language.t("about.version", build.isEmpty ? version : "\(version) (\(build))"))
                Text(verbatim: "·")
                Link("GitHub", destination: URL(string: "https://github.com/ReffWu/toknotch")!)
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.top, 20)

            Text(verbatim: "© 2026 Reff Wu")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
                .padding(.bottom, 28)
        }
        .frame(width: 360)
    }
}
