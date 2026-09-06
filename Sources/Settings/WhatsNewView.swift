import AppKit
import SwiftUI

/// What changed in this version, shown once when you first run it.
struct WhatsNewView: View {
    let note: ReleaseNote
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            // Scrolled rather than sized to fit. The window cannot grow, and a
            // release with a dozen entries would otherwise run off the bottom
            // of it — where the Continue button is.
            ScrollView { WhatsNewChanges(changes: note.changes) }
                .scrollBounceBehavior(.basedOnSize)

            Divider()
            HStack {
                Spacer(minLength: 0)
                Button("Continue", action: onContinue)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: WhatsNewView.width, height: WhatsNewView.height)
    }

    private var header: some View {
        VStack(spacing: 6) {
            if let icon = NSImage(named: "AppIcon") ?? NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 60, height: 60)
                    .padding(.bottom, 8)
            }
            Text("What's new in Codenotch")
                .font(.system(size: 19, weight: .semibold))
                .multilineTextAlignment(.center)
            Text("Version \(note.version)")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text(note.headline)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        }
        .padding(.horizontal, 28)
        .padding(.top, 26)
        .padding(.bottom, 20)
    }

    /// Narrow enough to read as a dialogue rather than a window, wide enough
    /// that a sentence of detail does not wrap every other word.
    static let width: CGFloat = 420
    /// Fixed, with the list scrolling inside it: a window that resizes itself
    /// to its content jumps between releases of different lengths.
    static let height: CGFloat = 440
}

/// The list of changes, on its own.
///
/// Separate from the dialogue because the dialogue scrolls it, and a
/// `ScrollView` draws nothing under `ImageRenderer` — so this is the piece a
/// test can actually look at.
struct WhatsNewChanges: View {
    let changes: [ReleaseNote.Change]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(changes.enumerated()), id: \.offset) { _, change in
                HStack(alignment: .top, spacing: 10) {
                    // The colour a healthy reading takes in the notch, at the
                    // size a list can carry.
                    Circle()
                        .fill(Palette.ample)
                        .frame(width: 6, height: 6)
                        .padding(.top, 6)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(change.title)
                            .font(.callout.weight(.medium))
                        // Absent rather than blank: a small fix is one line,
                        // not a line padded out to match its neighbours.
                        if !change.detail.isEmpty {
                            Text(change.detail)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 28)
        .padding(.bottom, 22)
    }
}
