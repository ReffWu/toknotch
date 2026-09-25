import AppKit
import SwiftUI

/// What changed in this version, shown once when you first run it.
/// Aligned with the Apple Music / macOS official What's New design standard.
struct WhatsNewView: View {
    let note: ReleaseNote
    /// Defaulted so a render test can make one without picking a language;
    /// the app always passes the one in settings.
    var language: AppLanguage = .english
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            // Scrolled rather than sized to fit. The window cannot grow, and a
            // release with multiple entries scrolls comfortably.
            ScrollView {
                WhatsNewChanges(changes: note.changes)
            }
            .scrollBounceBehavior(.basedOnSize)

            Spacer(minLength: 16)

            // 底部宽幅大胶囊主按钮（匹配 Apple Music 官方主行动按钮）
            Button(action: onContinue) {
                Text(language.t("whatsNew.continue"))
                    .font(.system(size: 13.5, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.ample)
            .clipShape(Capsule())
            .keyboardShortcut(.defaultAction)
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .frame(width: WhatsNewView.width, height: WhatsNewView.height)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(spacing: 6) {
            if let icon = NSImage(named: "AppIcon") ?? NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 58, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                    .padding(.bottom, 6)
            }
            Text(language.t("whatsNew.welcome"))
                .font(.system(size: 21, weight: .bold))
                .multilineTextAlignment(.center)
            Text(language.t("whatsNew.version", note.version))
                .font(.caption)
                .foregroundStyle(.tertiary)
            if !note.headline.isEmpty {
                Text(note.headline)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 18)
    }

    static let width: CGFloat = 430
    static let height: CGFloat = 470
}

/// The list of changes, presented with Apple-style feature icons.
struct WhatsNewChanges: View {
    let changes: [ReleaseNote.Change]

    private func symbol(for index: Int) -> (name: String, tint: Color) {
        let icons: [(String, Color)] = [
            ("sparkles", Palette.ample),
            ("app.badge.fill", .indigo),
            ("menubar.rectangle", .blue),
            ("slider.horizontal.3", .teal),
            ("bolt.fill", .orange)
        ]
        return icons[index % icons.count]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(Array(changes.enumerated()), id: \.offset) { index, change in
                let (sym, tint) = symbol(for: index)
                HStack(alignment: .top, spacing: 15) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(tint.gradient)
                        .frame(width: 38, height: 38)
                        .overlay(
                            Image(systemName: sym)
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(.white)
                        )
                        .shadow(color: tint.opacity(0.3), radius: 4, y: 2)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(change.title)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(Color.primary)
                        if !change.detail.isEmpty {
                            Text(change.detail)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .lineSpacing(2)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 32)
        .padding(.bottom, 12)
    }
}
