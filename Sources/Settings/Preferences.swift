import AppKit
import Combine
import Foundation
import ServiceManagement
import os

/// The language everything is written in.
///
/// Chosen in the app rather than followed from the system, because somebody
/// whose Mac is in English may still want their token counts grouped the way
/// they actually count — and the other way round. `.system` is there for
/// everybody who does not care.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case japanese = "ja"
    case korean = "ko"
    case german = "de"
    case french = "fr"
    case spanish = "es"
    case italian = "it"
    case brazilianPortuguese = "pt-BR"
    case dutch = "nl"
    case polish = "pl"
    case russian = "ru"
    case turkish = "tr"
    case vietnamese = "vi"
    case arabic = "ar"

    var id: String { rawValue }

    /// Each language named in itself.
    ///
    /// Somebody looking for Japanese is looking for 日本語, not for the word
    /// "Japanese" in a language they may not read. Only the system option is
    /// written in the current language, because it is the one entry that is not
    /// a language.
    var endonym: String {
        switch self {
        case .system:             return ""      // filled in by the caller
        case .english:            return "English"
        case .simplifiedChinese:  return "简体中文"
        case .traditionalChinese: return "繁體中文"
        case .japanese:           return "日本語"
        case .korean:             return "한국어"
        case .german:             return "Deutsch"
        case .french:             return "Français"
        case .spanish:            return "Español"
        case .italian:            return "Italiano"
        case .brazilianPortuguese: return "Português (Brasil)"
        case .dutch:              return "Nederlands"
        case .polish:             return "Polski"
        case .russian:            return "Русский"
        case .turkish:            return "Türkçe"
        case .vietnamese:         return "Tiếng Việt"
        case .arabic:             return "العربية"
        }
    }

    /// What Foundation formats numbers, money and dates against.
    ///
    /// This is where most of the localisation actually happens, and it is worth
    /// being explicit about how much it carries: the decimal separator, the
    /// grouping separator, where the currency symbol goes, and — the one that
    /// matters most here — how a large number is abbreviated. English counts in
    /// thousands (15.4B); Chinese, Japanese and Korean count in myriads
    /// (154.3亿 / 154.3億 / 154.3억); German writes 15,4 Mrd. and Russian
    /// 15,4 млрд. Writing "15.4B" for a Chinese reader forces an arithmetic
    /// conversion on every single glance, which is exactly what a readout on a
    /// screen edge must never do.
    var locale: Locale {
        switch self {
        case .system: return .autoupdatingCurrent
        // Western digits: token counts and prices read at a glance on a screen
        // edge, and they sit beside model names and prices that are Latin anyway.
        case .arabic: return Locale(identifier: "ar@numbers=latn")
        default: return Locale(identifier: rawValue)
        }
    }

    /// The best match among the languages we actually ship, for `.system`.
    var resolved: AppLanguage {
        guard self == .system else { return self }
        let preferred = Bundle.preferredLocalizations(
            from: AppLanguage.allCases.filter { $0 != .system }.map(\.rawValue)
        ).first
        return preferred.flatMap(AppLanguage.init(rawValue:)) ?? .english
    }
}

/// What the user has chosen, kept in `UserDefaults`.
@MainActor
final class Preferences: ObservableObject {
    /// Vendor rings the user has switched on, on top of the three primaries.
    ///
    /// Stored as the *enabled* set, which is the opposite of the old provider
    /// switch and deliberately so: the three primaries carry the app, and a
    /// vendor breakdown is something you go and ask for. A vendor added to the
    /// roster in a later version therefore stays quiet until it is wanted,
    /// instead of appearing on the notch unannounced.
    @Published var enabledVendors: Set<Vendor> {
        didSet { defaults.set(enabledVendors.map(\.rawValue), forKey: Keys.enabledVendors) }
    }

    /// What each vendor's plan costs and when it renews, for the payback
    /// figures on that vendor's card.
    ///
    /// Entered by hand and stored here rather than read from an account: doing
    /// it the other way would mean holding vendor credentials, which is the one
    /// thing this app promises not to do.
    @Published var subscriptions: [Vendor: Subscription] {
        didSet {
            let keyed = Dictionary(uniqueKeysWithValues:
                subscriptions.map { ($0.key.rawValue, $0.value) })
            defaults.set(try? JSONEncoder().encode(keyed), forKey: Keys.subscriptions)
        }
    }

    /// Vendors whose ring has already been switched on for them, once, because
    /// a plan was found for it.
    ///
    /// Remembered separately from `enabledVendors` so that turning one off
    /// stays off: without this, every launch would helpfully switch it back on
    /// and the setting would appear not to work. A vendor only ever gets this
    /// courtesy once.
    @Published private(set) var autoEnabledVendors: Set<Vendor> {
        didSet {
            defaults.set(autoEnabledVendors.map(\.rawValue), forKey: Keys.autoEnabled)
        }
    }

    /// Which settings page was open last. Reopening on the page you were last
    /// working in is the difference between a settings window and a filing
    /// cabinet you have to re-navigate every time.
    @Published var lastSettingsPage: String {
        didSet { defaults.set(lastSettingsPage, forKey: Keys.lastSettingsPage) }
    }

    /// Language and numerical units format (Chinese 万/亿 vs English k/M/B).
    @Published var appLanguage: AppLanguage {
        didSet { defaults.set(appLanguage.rawValue, forKey: Keys.language) }
    }

    /// How much of itself the notch shows at rest.
    @Published var notchVisibility: NotchVisibility {
        didSet { defaults.set(notchVisibility.rawValue, forKey: Keys.visibility) }
    }

    /// Which screen edge the notch is welded to.
    @Published var notchEdge: NotchEdge {
        didSet { defaults.set(notchEdge.rawValue, forKey: Keys.edge) }
    }

    /// Whether TokNotch also keeps a tile in the Dock. Off by default: the
    /// notch and the menu bar icon are how it is reached, and a tile for an app
    /// that never has a window open is one more thing to walk past.
    @Published var showsInDock: Bool {
        didSet { defaults.set(showsInDock, forKey: Keys.showsInDock) }
    }

    /// Whether the menu bar icon is there. On by default; somebody with a full
    /// menu bar can take it away, because the notch is always on screen and
    /// opening the app again still brings up Settings.
    @Published var showsMenuBarIcon: Bool {
        didSet { defaults.set(showsMenuBarIcon, forKey: Keys.showsMenuBarIcon) }
    }

    /// Whether anonymous daily heartbeat telemetry is shared. On by default.
    @Published var sharesUsageStatistics: Bool {
        didSet { defaults.set(sharesUsageStatistics, forKey: Keys.sharesUsageStatistics) }
    }

    /// The version whose changes have already been shown.
    ///
    /// Written when the What's New dialogue is dismissed rather than when it
    /// opens, so a crash in between cannot swallow the one launch it was going
    /// to appear on.
    @Published var lastSeenVersion: String? {
        didSet { defaults.set(lastSeenVersion, forKey: Keys.lastSeenVersion) }
    }

    private let defaults: UserDefaults
    private enum Keys {
        static let enabledVendors = "enabledVendors"
        static let subscriptions = "vendorSubscriptions"
        static let lastSettingsPage = "lastSettingsPage"
        static let autoEnabled = "autoEnabledVendors"
        static let hasLaunched = "hasLaunchedBefore"
        static let visibility = "notchVisibility"
        static let edge = "notchEdge"
        static let lastSeenVersion = "lastSeenVersion"
        static let language = "appLanguage"
        static let addedLoginItem = "addedLoginItem"
        static let showsInDock = "showsInDock"
        static let showsMenuBarIcon = "showsMenuBarIcon"
        static let sharesUsageStatistics = "sharesUsageStatistics"
    }

    /// True the very first time this copy runs, and never again.
    let isFirstLaunch: Bool

    /// The bundle identifiers this app has had before, newest first.
    ///
    /// A bundle id is the name of the defaults domain, so renaming the app
    /// silently moved every setting to a new, empty one — connection choices,
    /// the notch's mode, the archived readings, all apparently lost. Copying
    /// the most recent old domain across once is the difference between a
    /// rename and what looks like a reset.
    nonisolated private static let previousDomains = ["com.reff.toknotch", "com.reff.usagenotch"]

    static func migrateFromPreviousName(into defaults: UserDefaults = .standard) {
        for domain in previousDomains where defaults.object(forKey: Keys.hasLaunched) == nil {
            migrateFromPreviousName(into: defaults, from: domain)
        }
    }

    static func migrateFromPreviousName(into defaults: UserDefaults, from domain: String) {
        // The emptiness test has to be about the object being written to, not
        // about `Bundle.main` — under test those are different domains, and the
        // first version happily copied real settings into a test's scratch
        // suite. `hasLaunched` is the sentinel: `Preferences.init` sets it, so
        // its absence means nothing has ever used this domain.
        guard defaults.object(forKey: Keys.hasLaunched) == nil,
              let old = defaults.persistentDomain(forName: domain), !old.isEmpty
        else { return }

        for (key, value) in old { defaults.set(value, forKey: key) }
        Log.usage.info("migrated \(old.count) settings from the previous app name")
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isFirstLaunch = !defaults.bool(forKey: Keys.hasLaunched)
        defaults.set(true, forKey: Keys.hasLaunched)
        self.enabledVendors = Set((defaults.stringArray(forKey: Keys.enabledVendors) ?? [])
            .compactMap(Vendor.init(rawValue:)))
        let storedPlans = defaults.data(forKey: Keys.subscriptions)
            .flatMap { try? JSONDecoder().decode([String: Subscription].self, from: $0) } ?? [:]
        self.subscriptions = Dictionary(uniqueKeysWithValues: storedPlans.compactMap { key, plan in
            Vendor(rawValue: key).map { ($0, plan) }
        })
        // Absent means never chosen, which is the hover behaviour the app was
        // designed around. A "hidden" left by an older version lands here too.
        self.notchVisibility = defaults.string(forKey: Keys.visibility)
            .flatMap(NotchVisibility.init(rawValue:)) ?? .onHover
        if let stored = defaults.string(forKey: Keys.edge).flatMap(NotchEdge.init(rawValue:)) {
            self.notchEdge = stored
        } else if isFirstLaunch {
            // A Mac with a notch already has a black shape at the top of the
            // screen, and TokNotch grows out of it as if it had always been
            // there. Everywhere else the right edge is the one side no system
            // chrome claims. Decided once and kept, so plugging in a display
            // later cannot move it.
            let notched = NotchGeometry.preferredScreen(from: NSScreen.screens)?.hardwareNotch != nil
            let edge: NotchEdge = notched ? .top : .right
            self.notchEdge = edge
            defaults.set(edge.rawValue, forKey: Keys.edge)
        } else {
            // Somebody who never chose has been looking at the right edge.
            self.notchEdge = .right
        }
        // Absent means nothing has been shown yet, which is true of a fresh
        // install — so the current release reads as new to it.
        self.lastSeenVersion = defaults.string(forKey: Keys.lastSeenVersion)
        self.autoEnabledVendors = Set((defaults.stringArray(forKey: Keys.autoEnabled) ?? [])
            .compactMap(Vendor.init(rawValue:)))
        self.showsInDock = defaults.bool(forKey: Keys.showsInDock)
        self.showsMenuBarIcon = defaults.object(forKey: Keys.showsMenuBarIcon) as? Bool ?? true
        self.sharesUsageStatistics = defaults.object(forKey: Keys.sharesUsageStatistics) as? Bool ?? true
        self.lastSettingsPage = defaults.string(forKey: Keys.lastSettingsPage) ?? "payback"
        // Follows the Mac until somebody says otherwise, which is the right
        // default for a language: an app that opens in the wrong one is worse
        // than one that opens in the same language as everything else.
        self.appLanguage = defaults.string(forKey: Keys.language)
            .flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    func showsRing(for vendor: Vendor) -> Bool { enabledVendors.contains(vendor) }

    /// Switch on the ring for a vendor whose plan has just been recognised.
    ///
    /// The point is that finding a subscription is itself the answer to "do you
    /// want to see this vendor" — somebody paying Anthropic every month wants
    /// the Anthropic ring, and making them go and find the switch for it is
    /// asking a question the app already knows the answer to.
    func autoEnableRings(for vendors: [Vendor]) {
        let fresh = vendors.filter { !autoEnabledVendors.contains($0) }
        guard !fresh.isEmpty else { return }
        autoEnabledVendors.formUnion(fresh)
        enabledVendors.formUnion(fresh)
        Log.usage.notice("switched on \(fresh.count, privacy: .public) ring(s) for detected plans")
    }

    func subscription(for vendor: Vendor) -> Subscription? {
        subscriptions[vendor].flatMap { $0.isActive ? $0 : nil }
    }

    func setSubscription(_ plan: Subscription?, for vendor: Vendor) {
        if let plan, plan.isActive { subscriptions[vendor] = plan }
        else { subscriptions.removeValue(forKey: vendor) }
    }

    func setRing(_ shown: Bool, for vendor: Vendor) {
        if shown { enabledVendors.insert(vendor) } else { enabledVendors.remove(vendor) }
    }

    /// Forget everything this app has stored and quit.
    ///
    /// Deleting an app on macOS leaves `~/Library` untouched, so reinstalling
    /// brings back the old readings, the old connection choices and the old
    /// first-launch flag — which is exactly what makes a reinstall look broken.
    /// Nothing but the app itself can clean that up, so the app has to offer it.
    ///
    /// Not tied to uninstalling: a reinstall is indistinguishable from an
    /// update, and wiping data on every Sparkle update would be catastrophic.
    /// It has to be something the user asks for.
    static func eraseAllData() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.reffwu.toknotch"
        UserDefaults.standard.removePersistentDomain(forName: bundleID)
        UserDefaults.standard.synchronize()

        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
        for relative in ["Caches/\(bundleID)",
                         "WebKit/\(bundleID)",
                         "HTTPStorages/\(bundleID)",
                         "HTTPStorages/\(bundleID).binarycookies",
                         "Saved Application State/\(bundleID).savedState"] {
            if let url = library?.appendingPathComponent(relative) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    // MARK: - Login item

    /// Starts TokNotch with the Mac, once, without asking.
    ///
    /// A readout that lives on the screen edge is only useful if it is there
    /// every day, so opening at login is the right behaviour rather than a
    /// preference. It is done a single time: somebody who later removes it in
    /// System Settings has made a choice, and every launch re-adding it would
    /// overrule them.
    func addLoginItemOnce() {
        guard !defaults.bool(forKey: Keys.addedLoginItem) else { return }
        defaults.set(true, forKey: Keys.addedLoginItem)
        do {
            try SMAppService.mainApp.register()
        } catch {
            Log.usage.error("adding the login item failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
