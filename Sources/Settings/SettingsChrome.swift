import AppKit
import SwiftUI

/// The pieces every settings page is built from.
///
/// Deliberately not SwiftUI's `Form(.grouped)`. That style is built for long
/// lists of homogeneous rows and gives every one of them the same weight, so a
/// screen with three real decisions on it reads as a wall of identical controls
/// — which is exactly how this one used to read. These give a group a heading, a
/// card, and rows that can carry an icon, a subtitle and a control without any
/// of the three fighting the others.
enum SettingsMetrics {
    static let groupSpacing: CGFloat = 24
    static let cardCorner: CGFloat = 12
    static let rowPaddingH: CGFloat = 14
    static let rowPaddingV: CGFloat = 11
    /// The size System Settings gives a row's mark. Bigger than it first seems
    /// necessary — at 20pt the icon column reads as decoration, at 26 it reads
    /// as the thing you scan down.
    static let iconSize: CGFloat = 26
    static let iconCorner: CGFloat = 6.5
    /// Where a divider starts, so it clears the icon column.
    static let dividerInset: CGFloat = rowPaddingH + iconSize + 11
}

/// A titled group of rows on one card.
struct SettingsGroup<Content: View>: View {
    let title: String
    var footnote: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 2)

            VStack(spacing: 0) { content }
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: SettingsMetrics.cardCorner,
                                            style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: SettingsMetrics.cardCorner, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
                )

            if let footnote {
                Text(footnote)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 2)
                    .padding(.top, 1)
            }
        }
    }
}

/// The rounded, tinted square that carries a row's symbol — the mark macOS
/// settings uses to make a list of rows scannable rather than uniform.
struct SettingsIcon: View {
    let symbol: String
    var tint: Color = .accentColor

    var body: some View {
        RoundedRectangle(cornerRadius: SettingsMetrics.iconCorner, style: .continuous)
            .fill(tint.gradient)
            .frame(width: SettingsMetrics.iconSize, height: SettingsMetrics.iconSize)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: SettingsMetrics.iconSize * 0.55, weight: .semibold))
                    .foregroundStyle(.white)
            )
    }
}

/// One row: an optional mark, a title with an optional second line, and
/// whatever control belongs on the right.
struct SettingsRow<Leading: View, Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            leading
                .frame(width: SettingsMetrics.iconSize, height: SettingsMetrics.iconSize)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 10)
            trailing
        }
        .padding(.horizontal, SettingsMetrics.rowPaddingH)
        .padding(.vertical, SettingsMetrics.rowPaddingV)
    }
}

extension SettingsRow where Leading == SettingsIcon {
    init(_ symbol: String, tint: Color = .accentColor, title: String,
         subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.init(title: title, subtitle: subtitle,
                  leading: { SettingsIcon(symbol: symbol, tint: tint) },
                  trailing: trailing)
    }
}

/// A row that is a whole control rather than a label plus one — a segmented
/// picker, say, which needs the full width to stay legible.
struct SettingsStack<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 13))
            content
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, SettingsMetrics.rowPaddingH)
        .padding(.vertical, SettingsMetrics.rowPaddingV + 1)
    }
}

/// The rule between two rows, inset to clear the icon column.
struct SettingsDivider: View {
    var inset: CGFloat = SettingsMetrics.dividerInset

    var body: some View {
        Divider()
            .opacity(0.5)
            .padding(.leading, inset)
    }
}

/// A page: its groups, scrolled, with the margins every page shares.
struct SettingsPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsMetrics.groupSpacing) {
                content
            }
            .padding(EdgeInsets(top: 4, leading: 20, bottom: 24, trailing: 20))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // The window controls sit over the sidebar, not over this column, so
        // the page needs no allowance for them beyond its own margin.
        .contentMargins(.top, 26, for: .scrollContent)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}


/// A row whose choice is made from a pop-up menu on the right.
///
/// The shape System Settings uses for any multiple choice with nothing to
/// look at — "Text highlight color", "Folder color". Deliberately not a
/// segmented control spanning the row: that reads as the row's *content*
/// rather than as its setting, and it forces every option's full label onto
/// screen whether or not it earns the space.
struct SettingsMenuRow<T: Hashable & Identifiable>: View {
    let title: String
    var subtitle: String? = nil
    @Binding var selection: T
    let options: [T]
    let label: (T) -> String
    var symbol: String? = nil
    var tint: Color = .accentColor

    var body: some View {
        SettingsRow(
            title: title, subtitle: subtitle,
            leading: {
                if let symbol { SettingsIcon(symbol: symbol, tint: tint) }
            },
            trailing: {
                Picker("", selection: $selection) {
                    ForEach(options) { Text(label($0)).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
        )
    }
}

/// A row whose choices are pictures.
///
/// The shape System Settings uses for Light/Dark/Auto and for icon styles: the
/// options differ in something you can *see*, so showing it is worth more than
/// naming it. The selected one takes an accent ring, exactly as the system's
/// does.
struct SettingsPictureRow<T: Hashable & Identifiable, Preview: View>: View {
    let title: String
    var subtitle: String? = nil
    @Binding var selection: T
    let options: [T]
    let caption: (T) -> String
    @ViewBuilder let preview: (T) -> Preview

    static var previewSize: CGSize { CGSize(width: 62, height: 40) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13))
                }
                Spacer(minLength: 8)
                HStack(alignment: .top, spacing: 10) {
                    ForEach(options) { option in
                        VStack(spacing: 5) {
                            preview(option)
                                .frame(width: Self.previewSize.width,
                                       height: Self.previewSize.height)
                                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                                )
                                // The accent ring sits outside the artwork, as
                                // the system's does, so selecting something does
                                // not appear to shrink it.
                                .padding(2)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .strokeBorder(selection == option ? Color.accentColor : .clear,
                                                      lineWidth: 2.5)
                                )
                            Text(caption(option))
                                .font(.system(size: 10.5))
                                .foregroundStyle(selection == option ? .primary : .secondary)
                                .lineLimit(1)
                                .fixedSize()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { selection = option }
                    }
                }
            }
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, SettingsMetrics.rowPaddingH)
        .padding(.vertical, SettingsMetrics.rowPaddingV)
    }
}

/// The sidebar's own translucency.
///
/// `.regularMaterial` is close but not the same recipe macOS uses for a
/// sidebar, and side by side with the system's own settings window the
/// difference is visible. This is the real thing.
struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
