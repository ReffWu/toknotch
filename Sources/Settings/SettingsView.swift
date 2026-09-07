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

        func summary(_ language: AppLanguage) -> String {
            switch (self, language) {
            case (.rings, .chinese):
                return "选择刘海上显示哪些环。三个常驻环之外，你用过的每家服务商都能单独打开。"
            case (.rings, .english):
                return "Choose what the notch shows. Beyond the three that are always on, every vendor you've used can have a ring of its own."
            case (.plans, .chinese):
                return "填入每家的月费，就能看到这个计费周期里它产生的等效 API 价值是订阅费的多少倍。"
            case (.plans, .english):
                return "Enter what each plan costs and see what its usage has been worth against it, over the period the plan has actually paid for."
            case (.appearance, .chinese):
                return "刘海贴在哪条边、什么时候露出来，以及 TokNotch 本身出现在哪里。"
            case (.appearance, .english):
                return "Which edge the notch lives on, when it shows itself, and where TokNotch itself turns up."
            case (.general, .chinese):
                return "语言与数字写法、开机启动，以及用量数据从哪里来。"
            case (.general, .english):
                return "Language and number style, opening at login, and where the usage numbers come from."
            }
        }

        func title(_ language: AppLanguage) -> String {
            switch (self, language) {
            case (.rings, .chinese):      return "刘海显示"
            case (.rings, .english):      return "The notch"
            case (.plans, .chinese):      return "订阅与回本"
            case (.plans, .english):      return "Plans & payback"
            case (.appearance, .chinese): return "外观"
            case (.appearance, .english): return "Appearance"
            case (.general, .chinese):    return "通用"
            case (.general, .english):    return "General"
            }
        }
    }

    private var language: AppLanguage { preferences.appLanguage }
    private func t(_ chinese: String, _ english: String) -> String {
        language == .chinese ? chinese : english
    }

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
        .frame(width: SettingsView.width, height: SettingsView.height)
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
    private func t(_ zh: String, _ en: String) -> String { language == .chinese ? zh : en }

    var body: some View {
        SettingsPage {

            SettingsGroup(
                title: t("常驻的三个环", "Always shown"),
                footnote: t("这三个环始终显示。环的弧代表它跟什么比 — 走满一圈是你超过了自己，不是警告。",
                            "These three are always on. Each ring's arc is a comparison — a full ring means you beat your own best, not a warning.")
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
                title: t("按服务商拆分", "By vendor"),
                footnote: store.availableVendors.isEmpty ? nil
                    : t("每家一个环，显示它的累计用量与占全部用量的比例，默认全部关闭。列表来自本机实际用量 — 没用过的厂商不会出现。",
                        "One ring each, showing that vendor's lifetime usage and its share of everything. All off by default; the list comes from what this Mac has actually run.")
            ) {
                if store.availableVendors.isEmpty {
                    SettingsRow("hourglass", tint: .gray,
                                title: t("正在扫描本机用量…", "Scanning this Mac's usage…")) { EmptyView() }
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
        return "\(UsageFormat.tokens(totals.tokens, language)) · \(UsageFormat.money(totals.cost))"
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
        case .today:    return t("今日", "Today")
        case .month:    return t("本月", "This month")
        case .lifetime: return t("累计", "All time")
        case .vendor(let v): return v.title(language)
        }
    }

    private func primaryNote(_ kind: RingKind) -> String {
        switch kind {
        case .today:    return t("对比近 30 天最高的一天", "against your best day in 30")
        case .month:    return t("对比上月同期", "against the same days last month")
        case .lifetime: return t("距离下一个里程碑", "toward the next milestone")
        case .vendor:   return t("占全部用量", "share of everything")
        }
    }
}

// MARK: - Plans & payback

struct PlansPage: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var store: UsageStore

    private var language: AppLanguage { preferences.appLanguage }
    private func t(_ zh: String, _ en: String) -> String { language == .chinese ? zh : en }

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
                SettingsGroup(title: t("本期合计", "This period")) {
                    PaybackSummary(paid: totalMonthly, earned: totalEarned, language: language)
                }
            }

            SettingsGroup(
                title: t("每家的订阅", "Your plans"),
                footnote: t("套餐会自动认出来：Claude 读自它的配置文件，ChatGPT 读自 Codex 的登录态 — 只取套餐名与计费起始日，绝不读取密钥，也绝不外传。认不出的从菜单里挑一个即可，价格已内置。",
                            "Plans are recognised for you: Claude from its configuration file, ChatGPT from the Codex sign-in — only the plan name and the billing start date, never the keys beside them, and never off this Mac. Anything left over is one menu away.")
            ) {
                if vendors.isEmpty {
                    SettingsRow("hourglass", tint: .gray,
                                title: t("正在扫描本机用量…", "Scanning this Mac's usage…")) { EmptyView() }
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
                Text(language == .chinese ? "等效价值" : "Earned")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Text(UsageFormat.money(earned))
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

            Text(paidBack
                 ? (language == .chinese
                    ? "订阅共 \(UsageFormat.money(paid))/月 · 已超出 \(UsageFormat.money(earned - paid))"
                    : "\(UsageFormat.money(paid))/mo in plans · \(UsageFormat.money(earned - paid)) beyond break-even")
                 : (language == .chinese
                    ? "订阅共 \(UsageFormat.money(paid))/月 · 还差 \(UsageFormat.money(paid - earned))"
                    : "\(UsageFormat.money(paid))/mo in plans · \(UsageFormat.money(paid - earned)) to go"))
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

    private func t(_ zh: String, _ en: String) -> String { language == .chinese ? zh : en }

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
                        Text(language == .chinese ? "\(day) 号" : ordinal(day)).tag(day)
                    }
                }
                .labelsHidden()
                .frame(width: 68)
                .disabled(plan == nil)

                verdict.frame(width: 66, alignment: .trailing)
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
                        Text(language == .chinese ? "/ 月" : "/ mo")
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
    private var menuWidth: CGFloat { PlanCatalog.plans(for: vendor).isEmpty ? 84 : 162 }

    private func caption(for option: PlanCatalog.Plan) -> String {
        switch option.id {
        case "none":   return t("无订阅", "No plan")
        case "custom": return t("自定义…", "Custom…")
        default:
            return option.monthlyUSD > 0
                ? "\(option.name) · \(UsageFormat.moneyShort(option.monthlyUSD))"
                : option.name
        }
    }

    /// Says where a figure came from. The detected case is the one worth
    /// stating: a number that appeared without being typed needs to account
    /// for itself.
    private var provenance: String? {
        if isDetected, let detected {
            return t("自动识别：\(detected.name) · 读自 \(detected.source)",
                     "Detected: \(detected.name) · from \(detected.source)")
        }
        if let detected, detected.subscription != nil, !isDetected {
            return t("已手动覆盖（识别到 \(detected.name)）",
                     "Overridden (detected \(detected.name))")
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
                Text(payback.hasPaidBack ? t("已回本", "paid back") : t("回本中", "on the way"))
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
    private func t(_ zh: String, _ en: String) -> String { language == .chinese ? zh : en }

    var body: some View {
        SettingsPage {

            SettingsGroup(title: t("刘海", "The notch")) {
                SettingsPictureRow(
                    title: t("显示模式", "Show"),
                    subtitle: language == .chinese
                        ? preferences.notchVisibility.chineseExplanation
                        : preferences.notchVisibility.explanation,
                    selection: $preferences.notchVisibility,
                    options: NotchVisibility.allCases,
                    caption: { language == .chinese ? $0.chineseTitle : $0.title },
                    preview: { NotchVisibilityPreview(visibility: $0) }
                )
                SettingsDivider(inset: 0)
                SettingsPictureRow(
                    title: t("贴在哪条边", "Edge"),
                    subtitle: language == .chinese
                        ? preferences.notchEdge.chineseExplanation
                        : preferences.notchEdge.explanation,
                    selection: $preferences.notchEdge,
                    options: NotchEdge.allCases,
                    caption: { language == .chinese ? $0.chineseTitle : $0.title },
                    preview: { NotchEdgePreview(edge: $0) }
                )
            }

            SettingsGroup(title: t("应用本身", "The app itself"),
                          footnote: language == .chinese
                            ? preferences.appPresence.chineseExplanation
                            : preferences.appPresence.explanation) {
                SettingsMenuRow(
                    title: t("在哪里能找到它", "Where it shows up"),
                    selection: $preferences.appPresence,
                    options: AppPresence.allCases,
                    label: { language == .chinese ? $0.chineseTitle : $0.title },
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
    private func t(_ zh: String, _ en: String) -> String { language == .chinese ? zh : en }

    var body: some View {
        SettingsPage {

            SettingsGroup(title: t("语言与单位", "Language & units"),
                          footnote: preferences.appLanguage.explanation) {
                SettingsMenuRow(
                    title: t("数字怎么写", "How numbers are written"),
                    selection: $preferences.appLanguage,
                    options: AppLanguage.allCases,
                    label: { $0.title },
                    symbol: "textformat.123", tint: .teal
                )
            }

            SettingsGroup(title: t("启动", "Startup")) {
                SettingsRow("power", tint: .blue,
                            title: t("开机时自动启动", "Open at login"),
                            subtitle: preferences.launchAtLoginProblem) {
                    Toggle("", isOn: $preferences.launchAtLogin)
                        .toggleStyle(.switch).controlSize(.small).labelsHidden()
                }
            }

            SettingsGroup(
                title: t("数据来源", "Where the numbers come from"),
                footnote: t("用量由 tokscale 在本机扫描各个 AI 工具的会话记录得出；套餐则读自各工具的登录信息，只取套餐名与计费日。全程本地：不碰钥匙串、不弹密码框、不上传任何数据。",
                            "Usage comes from tokscale reading each tool's own session logs on this Mac; plans come from each tool's sign-in, and only the plan name and billing date are read. Entirely local: no keychain, no password prompts, nothing leaves the machine.")
            ) {
                SettingsRow(store.problem == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                            tint: store.problem == nil ? .green : .orange,
                            title: status, subtitle: source) {
                    Button(t("刷新", "Refresh")) { store.refreshNow() }
                        .controlSize(.small)
                        .disabled(store.isRefreshing)
                }
            }

            SettingsGroup(
                title: t("更新", "Updates"),
                footnote: Updater.isConfigured ? nil
                    : t("这份是本地构建，没有更新源 — 不是出错，只是它不是从发布渠道装的。",
                        "This is a local build with no update feed — not a fault, just a copy that did not come from a release.")
            ) {
                SettingsRow("arrow.triangle.2.circlepath", tint: .blue,
                            title: t("自动检查更新", "Check automatically"),
                            subtitle: updateStatus) {
                    Toggle("", isOn: $updater.automatic)
                        .toggleStyle(.switch).controlSize(.small).labelsHidden()
                        .disabled(!Updater.isConfigured)
                }
                SettingsDivider()
                SettingsRow("square.and.arrow.down", tint: .cyan,
                            title: t("现在检查", "Check now")) {
                    Button(t("检查", "Check")) { updater.checkForUpdates() }
                        .controlSize(.small)
                        .disabled(!Updater.isConfigured || updater.outcome == .checking)
                }
            }

            SettingsGroup(title: t("关于", "About")) {
                SettingsRow("app.badge", tint: .indigo,
                            title: "TokNotch \(updater.currentVersion)",
                            subtitle: t("刘海里的 Token 用量", "token usage, in the notch")) {
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
            return updater.lastChecked.map {
                let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short
                return t("上次检查 \(f.string(from: $0))", "Last checked \(f.string(from: $0))")
            }
        case .checking:            return t("正在检查…", "Checking…")
        case .upToDate:            return t("已是最新版本", "Up to date")
        case .found(let version):  return t("有新版本 \(version)", "Version \(version) is available")
        case .unreachable:         return t("暂时连不上更新源", "Couldn't reach the update feed")
        case .failed(let why):     return t("检查失败：\(why)", "Check failed — \(why)")
        }
    }

    private var status: String {
        if let problem = store.problem { return problem }
        guard let updated = store.lastUpdated else { return t("正在读取…", "Reading…") }
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return t("读取正常 · 更新于 \(formatter.string(from: updated))",
                 "Reading fine · updated \(formatter.string(from: updated))")
    }

    /// Says which copy of tokscale is answering, because "it is built in" is
    /// the whole reason this app needs no setup.
    private var source: String {
        TokscaleCLI.isUsingBundledBinary
            ? t("内置 tokscale \(TokscaleCLI.bundledVersion ?? "") — 无需另行安装",
                "Built-in tokscale \(TokscaleCLI.bundledVersion ?? "") — nothing to install")
            : t("使用本机安装的 tokscale", "Using the tokscale installed on this Mac")
    }
}
