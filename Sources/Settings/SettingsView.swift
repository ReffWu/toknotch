import AppKit
import SwiftUI

/// The settings window, reached from the orb below the notch.
///
/// Four pages behind a sidebar rather than one long scroll: the decisions here
/// fall into genuinely different kinds — what the notch shows, what the plans
/// cost, how it looks, and how the app behaves — and stacking them into a
/// single form made every one of them look equally important and equally dull.
struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var store: UsageStore
    @ObservedObject var updater: Updater

    @State private var page: Page = .rings
    /// Which page to open on. Only set by the render tests, which have to be
    /// able to photograph each one.
    var startingPage: Page? = nil

    enum Page: String, CaseIterable, Identifiable {
        case rings, plans, appearance, general
        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .rings:      return "circle.dashed"
            case .plans:      return "creditcard.fill"
            case .appearance: return "paintbrush.fill"
            case .general:    return "gearshape.fill"
            }
        }

        var tint: Color {
            switch self {
            case .rings:      return .orange
            case .plans:      return .green
            case .appearance: return .pink
            case .general:    return .gray
            }
        }

        func title(_ language: AppLanguage) -> String {
            language.t("settings.page." + rawValue)
        }
    }

    private var language: AppLanguage { preferences.appLanguage }

    var body: some View {
        // A plain split rather than `NavigationSplitView`. That view insists on
        // putting a sidebar-collapse button into the window's toolbar, and it
        // cannot be removed — which means a title bar has to exist to hold it,
        // and a button whose only offer is to hide the one control that makes
        // this window navigable. Two columns side by side owe nobody a toolbar.
        HStack(spacing: 0) {
            sidebar
                .frame(width: SettingsView.sidebarWidth)
                .background(SidebarMaterial())
            Divider()
            detail
        }
        // Fills whatever the window gives it rather than claiming a fixed
        // size. With `fullSizeContentView` the window's content area includes
        // the title bar's height, so a hard-coded height leaves a band of bare
        // window showing along the bottom edge.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .onAppear {
            page = startingPage
                ?? Page(rawValue: preferences.lastSettingsPage)
                ?? .rings
        }
        .onChange(of: page) { _, new in preferences.lastSettingsPage = new.rawValue }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Clear of the window controls, which sit over the sidebar now that
            // there is no title bar for them to live in.
            Color.clear.frame(height: 42)

            ForEach(Page.allCases) { item in
                Button {
                    page = item
                } label: {
                    HStack(spacing: 10) {
                        SettingsIcon(symbol: item.symbol, tint: item.tint)
                        Text(item.title(language))
                            .font(.system(size: 13))
                            .foregroundStyle(page == item ? Color.white : Color.primary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(page == item ? Color.accentColor : .clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
    }

    @ViewBuilder
    private var detail: some View {
        switch page {
        case .rings:      RingsPage(preferences: preferences, store: store)
        case .plans:      PlansPage(preferences: preferences, store: store)
        case .appearance: AppearancePage(preferences: preferences)
        case .general:    GeneralPage(preferences: preferences, store: store, updater: updater)
        }
    }

    static let sidebarWidth: CGFloat = 178
    static let width: CGFloat = 700
    static let height: CGFloat = 650
}

// MARK: - What the notch shows

struct RingsPage: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var store: UsageStore

    private var language: AppLanguage { preferences.appLanguage }

    var body: some View {
        SettingsPage {

            SettingsGroup(
                title: language.t("settings.alwaysShown"),
                footnote: language.t("settings.theseThreeAreAlwaysOn")
            ) {
                ForEach(Array(RingKind.primaries.enumerated()), id: \.element.id) { index, kind in
                    if index > 0 { SettingsDivider() }
                    SettingsRow(
                        title: primaryTitle(kind),
                        subtitle: primaryNote(kind),
                        leading: { RingGlyphView(glyph: glyph(for: kind), size: 17)
                            .foregroundStyle(.primary) },
                        trailing: { headline(for: kind) }
                    )
                }
            }

            SettingsGroup(
                title: language.t("settings.byVendor"),
                footnote: store.availableVendors.isEmpty ? nil
                    : language.t("settings.oneRingEachShowingThat")
            ) {
                if store.availableVendors.isEmpty {
                    SettingsRow("hourglass", tint: .gray,
                                title: language.t("settings.scanningThisMacSUsage")) { EmptyView() }
                } else {
                    ForEach(Array(store.availableVendors.enumerated()), id: \.element.rawValue) { index, vendor in
                        if index > 0 { SettingsDivider() }
                        SettingsRow(
                            title: vendor.title(language),
                            subtitle: subtitle(for: vendor),
                            leading: { RingGlyphView(glyph: .vendor(vendor), size: 17)
                                .foregroundStyle(vendor.ringTint) },
                            trailing: {
                                Toggle("", isOn: Binding(
                                    get: { preferences.showsRing(for: vendor) },
                                    set: { preferences.setRing($0, for: vendor) }
                                ))
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .labelsHidden()
                            }
                        )
                    }
                }
            }
        }
    }

    private func subtitle(for vendor: Vendor) -> String? {
        guard let totals = store.lifetime(for: vendor) else { return nil }
        return "\(UsageFormat.tokens(totals.tokens, language)) · \(UsageFormat.money(totals.cost, language))"
    }

    @ViewBuilder
    private func headline(for kind: RingKind) -> some View {
        if let ring = store.rings.first(where: { $0.kind == kind }), ring.hasReading {
            Text(ring.headline)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func glyph(for kind: RingKind) -> RingGlyph {
        switch kind {
        case .today:         return .today
        case .month:         return .month
        case .lifetime:      return .lifetime
        case .vendor(let v): return .vendor(v)
        }
    }

    private func primaryTitle(_ kind: RingKind) -> String {
        switch kind {
        case .today:    return language.t("settings.today")
        case .month:    return language.t("settings.thisMonth")
        case .lifetime: return language.t("settings.allTime")
        case .vendor(let v): return v.title(language)
        }
    }

    private func primaryNote(_ kind: RingKind) -> String {
        switch kind {
        case .today:    return language.t("settings.againstYourBestDayIn")
        case .month:    return language.t("settings.againstTheSameDaysLast")
        case .lifetime: return language.t("settings.towardTheNextMilestone")
        case .vendor:   return language.t("settings.shareOfEverything")
        }
    }
}

// MARK: - Plans & payback

struct PlansPage: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var store: UsageStore

    private var language: AppLanguage { preferences.appLanguage }

    /// Vendors you can actually hold a plan with, and that this Mac has used.
    ///
    /// Deliberately not every vendor in the stack: DeepSeek, MiniMax, Qwen and
    /// the rest are billed by the token here, so a row asking what their
    /// subscription costs is a question with no answer — and nine such rows
    /// bury the two that matter.
    private var vendors: [Vendor] {
        store.availableVendors.filter { !PlanCatalog.plans(for: $0).isEmpty }
    }

    private var configured: [(Vendor, Subscription)] {
        vendors.compactMap { vendor in store.plan(for: vendor).map { (vendor, $0) } }
    }

    private var totalMonthly: Double { configured.reduce(0) { $0 + $1.1.monthlyUSD } }
    private var totalEarned: Double {
        configured.reduce(0) { $0 + (store.payback(for: $1.0, plan: $1.1)?.earned ?? 0) }
    }

    var body: some View {
        SettingsPage {

            if !configured.isEmpty {
                SettingsGroup(title: language.t("settings.thisPeriod")) {
                    PaybackSummary(paid: totalMonthly, earned: totalEarned, language: language)
                }
            }

            SettingsGroup(
                title: language.t("settings.yourPlans"),
                footnote: language.t("settings.plansAreRecognisedForYou")
            ) {
                if vendors.isEmpty {
                    SettingsRow("hourglass", tint: .gray,
                                title: language.t("settings.scanningThisMacSUsage")) { EmptyView() }
                } else {
                    ForEach(Array(vendors.enumerated()), id: \.element.rawValue) { index, vendor in
                        if index > 0 { SettingsDivider(inset: 0) }
                        PlanRow(vendor: vendor, preferences: preferences,
                                store: store, language: language)
                    }
                }
            }
        }
    }
}

/// The one line the plans page exists to produce.
private struct PaybackSummary: View {
    let paid: Double
    let earned: Double
    let language: AppLanguage

    private var multiple: Double { paid > 0 ? earned / paid : 0 }
    private var paidBack: Bool { multiple >= 1 }
    private var scale: PaybackScale { .around(multiple) }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(language.t("settings.earned"))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Text(UsageFormat.money(earned, language))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Spacer()
                Text(String(format: "%.1f×", multiple))
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(paidBack ? Color.green : Color.orange)
                    .monospacedDigit()
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.09))
                    Capsule()
                        .fill((paidBack ? Color.green : Color.orange).gradient)
                        .frame(width: max(4, proxy.size.width * scale.fill(multiple)))
                    if let breakEven = scale.breakEven {
                        // Break-even, cut into the bar in the card's own colour.
                        // Once a plan is well past paying for itself the fill
                        // alone says nothing; where this tick sits is the whole
                        // reading.
                        Capsule()
                            .fill(Color(nsColor: .controlBackgroundColor))
                            .frame(width: 2)
                            .offset(x: proxy.size.width * breakEven - 1)
                    }
                }
            }
            .frame(height: 6)

            Text(language.t(paidBack ? "settings.plansTotalOver" : "settings.plansTotalToGo",
                            UsageFormat.money(paid, language),
                            UsageFormat.money(abs(earned - paid), language)))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, SettingsMetrics.rowPaddingH)
        .padding(.vertical, 11)
    }
}

/// One vendor's plan: what it is, when it renews, and how it is doing.
///
/// A menu of the vendor's own plans rather than a box to type a number into.
/// Nobody holds "20" — they hold Claude Pro — and looking a list price up is
/// work the app can do once for everybody. Where the plan can be read out of
/// the tool's own configuration it is simply already selected.
private struct PlanRow: View {
    let vendor: Vendor
    @ObservedObject var preferences: Preferences
    @ObservedObject var store: UsageStore
    let language: AppLanguage

    /// Shown only while "custom" is chosen, and committed on Return or on
    /// losing focus — a field bound straight to a number rewrites itself on
    /// every keystroke, so editing 200 into 20 passes through whatever the
    /// half-typed text parses to.
    @State private var draft: String = ""
    @FocusState private var editing: Bool


    private var detected: DetectedPlan? { store.detectedPlans[vendor] }
    private var plan: Subscription? { store.plan(for: vendor) }
    private var isDetected: Bool { store.isDetected(vendor) }
    private var isCustom: Bool { plan != nil && plan?.planID == nil }

    private var menu: [PlanCatalog.Plan] { PlanCatalog.menu(for: vendor) }

    private var selected: PlanCatalog.Plan {
        guard let plan else { return .none }
        if let id = plan.planID, let known = PlanCatalog.plan(id: id, for: vendor) { return known }
        return plan.isActive ? .custom : .none
    }

    private var selection: Binding<PlanCatalog.Plan> {
        Binding(
            get: { selected },
            set: { choice in
                // A Picker may call this during layout with the value it just
                // read. Storing that unconditionally is how vendors nobody had
                // touched ended up with plans of their own.
                guard choice != selected else { return }
                let day = plan?.renewalDay ?? detected?.renewalDay ?? 1
                switch choice.id {
                case "none":
                    // An explicit "no plan", which has to outrank detection —
                    // hence a stored zero rather than removing the entry.
                    preferences.subscriptions[vendor] = Subscription(monthlyUSD: 0, renewalDay: day)
                case "custom":
                    preferences.subscriptions[vendor] =
                        Subscription(monthlyUSD: plan?.monthlyUSD ?? 0, renewalDay: day)
                    draft = plan.map { trimmed($0.monthlyUSD) } ?? ""
                    editing = true
                default:
                    preferences.subscriptions[vendor] =
                        Subscription(monthlyUSD: choice.monthlyUSD, renewalDay: day,
                                     planID: choice.id)
                }
            }
        )
    }

    private var renewalDay: Binding<Int> {
        Binding(
            get: { plan?.renewalDay ?? detected?.renewalDay ?? 1 },
            set: { day in
                // Only a vendor that actually has a plan has a renewal day, and
                // only a real change is worth storing.
                guard let current = plan, current.renewalDay != day else { return }
                preferences.subscriptions[vendor] =
                    Subscription(monthlyUSD: current.monthlyUSD, renewalDay: day,
                                 planID: current.planID)
            }
        )
    }

    private var payback: Payback? {
        plan.flatMap { store.payback(for: vendor, plan: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 9) {
                RingGlyphView(glyph: .vendor(vendor), size: 17)
                    .foregroundStyle(vendor.ringTint)
                    .frame(width: SettingsMetrics.iconSize)

                Text(vendor.title(language))
                    .font(.system(size: 13))
                    .lineLimit(1)
                    // Without this the name is the one flexible thing in a full
                    // row, so it is what gets squeezed away to nothing.
                    .layoutPriority(1)
                Spacer(minLength: 6)

                Picker("", selection: selection) {
                    ForEach(menu) { Text(caption(for: $0)).tag($0) }
                }
                .labelsHidden()
                .frame(width: menuWidth)

                Picker("", selection: renewalDay) {
                    ForEach(1...31, id: \.self) { day in
                        Text(language.t("settings.dayOfMonth", day)).tag(day)
                    }
                }
                .labelsHidden()
                .frame(width: 68)
                .disabled(plan == nil)

                verdict.frame(width: 86, alignment: .trailing)
            }

            if isCustom || provenance != nil {
                HStack(spacing: 6) {
                    if isCustom {
                        Text("$").font(.system(size: 11)).foregroundStyle(.secondary)
                        TextField("0", text: $draft)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 62)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .focused($editing)
                            .onSubmit(commit)
                            .onChange(of: editing) { _, focused in if !focused { commit() } }
                        Text(language.t("settings.perMonth"))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    if let note = provenance {
                        Text(note).font(.system(size: 10.5)).foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, SettingsMetrics.iconSize + 9)
            }
        }
        .padding(.horizontal, SettingsMetrics.rowPaddingH)
        .padding(.vertical, 8)
        .onAppear { draft = plan.map { trimmed($0.monthlyUSD) } ?? "" }
    }

    /// Menus of long plan names need room; a vendor with no plans at all only
    /// ever shows "—" and "…".
    /// Wide enough for the longest plan name and its price together —
    /// "ChatGPT Plus · $20" truncated to "ChatGPT Plus ·…", which reads as
    /// though something is missing.
    private var menuWidth: CGFloat { PlanCatalog.plans(for: vendor).isEmpty ? 84 : 156 }

    private func caption(for option: PlanCatalog.Plan) -> String {
        switch option.id {
        case "none":   return language.t("settings.noPlan")
        case "custom": return language.t("settings.custom")
        default:
            return option.monthlyUSD > 0
                ? "\(option.name) · \(UsageFormat.moneyShort(option.monthlyUSD, language))"
                : option.name
        }
    }

    /// Says where a figure came from. The detected case is the one worth
    /// stating: a number that appeared without being typed needs to account
    /// for itself.
    private var provenance: String? {
        if isDetected, let detected {
            return language.t("settings.detected", detected.name, detected.source)
        }
        if let detected, detected.subscription != nil, !isDetected {
            return language.t("settings.overridden", detected.name)
        }
        return nil
    }

    private func commit() {
        // Only ever writes while the custom field is the thing on screen.
        guard isCustom else { return }
        let cleaned = draft.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
        let value = Double(cleaned) ?? 0
        preferences.subscriptions[vendor] =
            Subscription(monthlyUSD: value, renewalDay: renewalDay.wrappedValue)
        draft = value > 0 ? trimmed(value) : ""
    }

    private func trimmed(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value)
    }

    private func ordinal(_ day: Int) -> String {
        let suffix: String
        switch (day % 10, day % 100) {
        case (1, 11), (2, 12), (3, 13): suffix = "th"
        case (1, _): suffix = "st"
        case (2, _): suffix = "nd"
        case (3, _): suffix = "rd"
        default: suffix = "th"
        }
        return "\(day)\(suffix)"
    }

    @ViewBuilder
    private var verdict: some View {
        if let payback {
            VStack(alignment: .trailing, spacing: 0) {
                Text(String(format: "%.1f×", payback.multiple))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(payback.hasPaidBack ? language.t("settings.paidBack") : language.t("settings.onTheWay"))
                    .font(.system(size: 10))
            }
            .foregroundStyle(payback.hasPaidBack ? Color.green : Color.orange)
        } else {
            Text("—").font(.system(size: 13)).foregroundStyle(.quaternary)
        }
    }
}

// MARK: - Appearance

struct AppearancePage: View {
    @ObservedObject var preferences: Preferences

    private var language: AppLanguage { preferences.appLanguage }

    var body: some View {
        SettingsPage {

            SettingsGroup(title: language.t("settings.theNotch")) {
                SettingsPictureRow(
                    title: language.t("settings.show"),
                    subtitle: preferences.notchVisibility.explanation(language),
                    selection: $preferences.notchVisibility,
                    options: NotchVisibility.allCases,
                    caption: { $0.title(language) },
                    preview: { NotchVisibilityPreview(visibility: $0) }
                )
                SettingsDivider(inset: 0)
                SettingsPictureRow(
                    title: language.t("settings.edge"),
                    subtitle: preferences.notchEdge.explanation(language),
                    selection: $preferences.notchEdge,
                    options: NotchEdge.allCases,
                    caption: { $0.title(language) },
                    preview: { NotchEdgePreview(edge: $0) }
                )
            }

            SettingsGroup(title: language.t("settings.theAppItself"),
                          footnote: preferences.appPresence.explanation(language)) {
                SettingsMenuRow(
                    title: language.t("settings.whereItShowsUp"),
                    selection: $preferences.appPresence,
                    options: AppPresence.allCases,
                    label: { $0.title(language) },
                    symbol: "macwindow", tint: .indigo
                )
            }
        }
    }
}

// MARK: - General

struct GeneralPage: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var store: UsageStore
    @ObservedObject var updater: Updater

    private var language: AppLanguage { preferences.appLanguage }

    var body: some View {
        SettingsPage {

            SettingsGroup(title: language.t("settings.language"),
                          footnote: language.t("settings.languageNote")) {
                SettingsMenuRow(
                    title: language.t("settings.language"),
                    selection: $preferences.appLanguage,
                    options: AppLanguage.available,
                    // Each language named in itself; only "system" is written
                    // in whatever the reader is currently using.
                    label: { $0 == .system ? language.t("settings.systemLanguage") : $0.endonym },
                    symbol: "globe", tint: .teal
                )
            }

            SettingsGroup(title: language.t("settings.startup")) {
                SettingsRow("power", tint: .blue,
                            title: language.t("settings.openAtLogin"),
                            subtitle: preferences.launchAtLoginProblem) {
                    Toggle("", isOn: $preferences.launchAtLogin)
                        .toggleStyle(.switch).controlSize(.small).labelsHidden()
                }
            }

            SettingsGroup(
                title: language.t("settings.whereTheNumbersComeFrom"),
                footnote: language.t("settings.usageComesFromTokscaleReading")
            ) {
                SettingsRow(store.problem == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                            tint: store.problem == nil ? .green : .orange,
                            title: status, subtitle: source) {
                    Button(language.t("settings.refresh")) { store.refreshNow() }
                        .controlSize(.small)
                        .disabled(store.isRefreshing)
                }
            }

            SettingsGroup(
                title: language.t("settings.updates"),
                footnote: Updater.isConfigured ? nil
                    : language.t("settings.thisIsALocalBuild")
            ) {
                SettingsRow("arrow.triangle.2.circlepath", tint: .blue,
                            title: language.t("settings.checkAutomatically"),
                            subtitle: updateStatus) {
                    Toggle("", isOn: $updater.automatic)
                        .toggleStyle(.switch).controlSize(.small).labelsHidden()
                        .disabled(!Updater.isConfigured)
                }
                SettingsDivider()
                SettingsRow("square.and.arrow.down", tint: .cyan,
                            title: language.t("settings.checkNow")) {
                    Button(language.t("settings.check")) { updater.checkForUpdates() }
                        .controlSize(.small)
                        .disabled(!Updater.isConfigured || updater.outcome == .checking)
                }
            }

            SettingsGroup(title: language.t("settings.about")) {
                SettingsRow("app.badge", tint: .indigo,
                            title: "TokNotch \(updater.currentVersion)",
                            subtitle: language.t("settings.tokenUsageInTheNotch")) {
                    EmptyView()
                }
            }
        }
    }

    /// What the updater is currently able to say for itself.
    private var updateStatus: String? {
        switch updater.outcome {
        case .unconfigured: return nil
        case .idle:
            return updater.lastChecked.map { checked in
                let f = DateFormatter()
                f.locale = language.locale
                f.dateStyle = .medium
                f.timeStyle = .short
                return language.t("settings.lastChecked", f.string(from: checked))
            }
        case .checking:            return language.t("settings.checking")
        case .upToDate:            return language.t("settings.upToDate")
        case .found(let version):  return language.t("settings.updateAvailable", version)
        case .unreachable:         return language.t("settings.couldnTReachTheUpdate")
        case .failed(let why):     return language.t("settings.checkFailed", why)
        }
    }

    private var status: String {
        if let problem = store.problem { return problem }
        guard let updated = store.lastUpdated else { return language.t("settings.reading") }
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return language.t("settings.readingFine", formatter.string(from: updated))
    }

    /// Says which copy of tokscale is answering, because "it is built in" is
    /// the whole reason this app needs no setup.
    private var source: String {
        TokscaleCLI.isUsingBundledBinary
            ? language.t("settings.builtInTokscale", TokscaleCLI.bundledVersion ?? "")
            : language.t("settings.usingTheTokscaleInstalledOn")
    }
}
