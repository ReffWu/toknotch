import AppKit
import SwiftUI

/// What the menu bar icon opens.
///
/// Somebody clicks it with one of two questions: "have my plans paid for
/// themselves yet?" and "how much have I used?". The answer to the first is
/// the largest thing in the panel, the second is three figures side by side,
/// and everything a menu bar app is eventually needed for — settings, updates,
/// quit — sits at the foot, always in the same place.
struct MenuBarPanel: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var store: UsageStore
    @ObservedObject var updater: Updater
    let onOpenSettings: () -> Void
    let onAbout: () -> Void

    private var language: AppLanguage { preferences.appLanguage }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let problem = store.problem {
                ProblemCard(text: problem, language: language, isRefreshing: store.isRefreshing) {
                    store.refreshNow(byHand: true)
                }
            }
            payback
            periods
            if plans.count > 1 { vendors }
            Divider().padding(.horizontal, 6)
            actions
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .frame(width: Self.width)
        // The menu's glass alone lets a busy window behind show through the
        // figures; a frosted layer keeps them readable over anything.
        .background(.regularMaterial)
    }

    static let width: CGFloat = 320

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: onAbout) {
                Text(verbatim: "TokNotch").font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.plain)
            .help(language.t("menu.about"))

            Spacer(minLength: 8)

            if let updated = store.lastUpdated {
                // Re-read every half minute, so "1 minute ago" does not sit
                // there saying so for an hour.
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(updated.formatted(.relative(presentation: .named)
                        .locale(language.locale)))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .id(context.date)
                }
            }

            RefreshButton(isRefreshing: store.isRefreshing, help: language.t("settings.refresh")) {
                store.refreshNow(byHand: true)
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: Payback

    /// Every plan in force, busiest earner first.
    private var plans: [(vendor: Vendor, payback: Payback)] {
        store.availableVendors
            .compactMap { vendor in
                store.plan(for: vendor)
                    .flatMap { store.payback(for: vendor, plan: $0) }
                    .map { (vendor, $0) }
            }
            .sorted { $0.payback.multiple > $1.payback.multiple }
    }

    @ViewBuilder
    private var payback: some View {
        if let total = store.periodPayback(), total.paid > 0 {
            PaybackHero(paid: total.paid, earned: total.earned, language: language)
        } else if store.lastUpdated != nil {
            // Not a zero: with no plan there is nothing to have paid back, and
            // the one useful thing to offer is the place to say what you pay.
            Button(action: onOpenSettings) {
                HStack(spacing: 10) {
                    SettingsIcon(symbol: "creditcard.fill", tint: .green)
                    Text(language.t("menu.pickAPlan"))
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .panelCard()
        }
    }

    // MARK: Today · Month · Lifetime

    private var periods: some View {
        HStack(spacing: 8) {
            ForEach(RingKind.primaries.reversed(), id: \.self) { kind in
                PeriodTile(ring: store.rings.first { $0.kind == kind }, kind: kind, language: language)
            }
        }
    }

    // MARK: Vendors

    /// Each plan on its own line, once there is more than one: with a single
    /// plan the hero above already is that plan.
    private var vendors: some View {
        VStack(spacing: 0) {
            ForEach(Array(plans.enumerated()), id: \.element.vendor.rawValue) { index, entry in
                if index > 0 { Divider().padding(.leading, 36).opacity(0.5) }
                HStack(spacing: 10) {
                    RingGlyphView(glyph: .vendor(entry.vendor), size: 15)
                        .foregroundStyle(entry.vendor.ringTint)
                        .frame(width: 16)
                    Text(entry.vendor.title(language))
                        .font(.system(size: 12))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(UsageFormat.money(entry.payback.earned, language))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Text(String(format: "%.1f×", entry.payback.multiple))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(entry.vendor.tint)
                        .monospacedDigit()
                        .frame(minWidth: 44, alignment: .trailing)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
        }
        .panelCard()
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: 0) {
            PanelAction(symbol: "gearshape", title: language.t("menu.open"), shortcut: "⌘,",
                        action: onOpenSettings)
                .keyboardShortcut(",")
            if Updater.isConfigured {
                PanelAction(symbol: "arrow.triangle.2.circlepath",
                            title: updater.outcome.label(language),
                            badge: updater.outcome.isFound) {
                    updater.checkForUpdates()
                }
                .disabled(updater.outcome == .checking)
            }
            PanelAction(symbol: "power", title: language.t("menu.quit"), shortcut: "⌘Q") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}

// MARK: - Pieces

/// The headline: how many times over every plan has paid for itself.
private struct PaybackHero: View {
    let paid: Double
    let earned: Double
    let language: AppLanguage

    private var multiple: Double { paid > 0 ? earned / paid : 0 }
    private var paidBack: Bool { multiple >= 1 }
    private var scale: PaybackScale { .around(multiple) }
    private var tint: Color { paidBack ? .green : .orange }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(language.t("settings.thisPeriod"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(String(format: "%.1f×", multiple))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(language.t(paidBack ? "payback.paidBack" : "payback.onTheWay"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(tint.opacity(0.15)))
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(language.t("settings.earned"))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(UsageFormat.money(earned, language))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.1))
                    Capsule()
                        .fill(tint.gradient)
                        .frame(width: max(5, proxy.size.width * scale.fill(multiple)))
                    if let breakEven = scale.breakEven {
                        // Break-even, cut clean through the bar, so it reads
                        // against whatever the panel's material shows behind it.
                        Rectangle()
                            .frame(width: 2)
                            .offset(x: proxy.size.width * breakEven - 1)
                            .blendMode(.destinationOut)
                    }
                }
                .compositingGroup()
            }
            .frame(height: 6)

            Text(language.t(paidBack ? "settings.plansTotalOver" : "settings.plansTotalToGo",
                            UsageFormat.money(paid, language),
                            UsageFormat.money(abs(earned - paid), language)))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(12)
        .panelCard()
    }
}

/// One of today, this month and all time: tokens large, what they are worth
/// beneath.
private struct PeriodTile: View {
    let ring: RingSnapshot?
    let kind: RingKind
    let language: AppLanguage

    private var title: String {
        switch kind {
        case .today:    return language.t("ring.today.title")
        case .month:    return language.t("ring.month.title")
        default:        return language.t("ring.lifetime.title")
        }
    }

    private var glyph: RingGlyph {
        switch kind {
        case .today:    return .today
        case .month:    return .month
        default:        return .lifetime
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                RingGlyphView(glyph: glyph, size: 10)
                Text(title)
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

            Text(ring?.hasReading == true ? ring!.hero : "—")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())

            Text(ring?.rows.first { $0.id == "cost" }?.value ?? " ")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .panelCard()
    }
}

private struct ProblemCard: View {
    let text: String
    let language: AppLanguage
    let isRefreshing: Bool
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(text)
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(language.t("settings.refresh"), action: retry)
                .controlSize(.small)
                .disabled(isRefreshing)
        }
        .padding(10)
        .panelCard()
    }
}

/// Turns once per read, like the rings on the notch.
private struct RefreshButton: View {
    let isRefreshing: Bool
    let help: String
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin: Double = 0
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(spin))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.primary.opacity(hovering ? 0.08 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isRefreshing)
        .onHover { hovering = $0 }
        .help(help)
        .onChange(of: isRefreshing) { _, refreshing in
            guard refreshing, !reduceMotion else { return }
            withAnimation(.timingCurve(0.32, 0, 0.14, 1, duration: 0.95)) { spin += 360 }
        }
    }
}

/// A line at the foot of the panel, drawn and highlighted the way a menu item is.
private struct PanelAction: View {
    let symbol: String
    let title: String
    var shortcut: String? = nil
    var badge = false
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                if badge {
                    Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                }
                Spacer(minLength: 8)
                if let shortcut {
                    Text(verbatim: shortcut)
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(hovering && isEnabled ? 0.09 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.5)
        .onHover { hovering = $0 }
    }
}

private extension View {
    /// The panel's cards: a tint on the menu's own material rather than a
    /// solid fill, so they sit in it the way Control Center's modules do.
    func panelCard() -> some View {
        background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}
