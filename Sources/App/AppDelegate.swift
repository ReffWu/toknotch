import AppKit
import Combine
import SwiftUI

/// What the menu bar panel reads. Nil until launch has built it.
struct MenuBarContext {
    let preferences: Preferences
    let store: UsageStore
    let updater: Updater
    let openSettings: () -> Void
    let about: () -> Void
}

final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    @Published private(set) var menuBar: MenuBarContext?
    private var notchController: NotchWindowController?
    private var store: UsageStore?
    private var preferences: Preferences?
    private var settings: SettingsWindowController?
    private var whatsNew: WhatsNewWindowController?
    private var about: AboutWindowController?
    /// Held for the life of the app: releasing it stops the scheduled checks.
    private var updater: Updater?
    private var cancellables = Set<AnyCancellable>()

    /// The unit bundle is hosted by this app, so `xcodebuild test` launches it
    /// for real. Without this guard every test run put a live request on the
    /// usage endpoint — which is both wrong on its own terms and, on an endpoint
    /// that rate-limits, actively harmful.
    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }
    private var isRunningTests: Bool { Self.isRunningTests }

    /// No menu bar icon under test or in a demo run, where there is nothing
    /// behind it to open.
    static var hasMenuBarIcon: Bool {
        !isRunningTests && ProcessInfo.processInfo.environment["TOKNOTCH_DEMO"] != "1"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // No Dock tile unless asked for: the notch and the menu bar icon are
        // how TokNotch is reached. `LSUIElement` in the Info.plist keeps the
        // tile from flashing up at launch; this keeps a copy registered before
        // that key existed from holding on to one. The Show in Dock setting
        // puts it back below.
        NSApp.setActivationPolicy(.accessory)
        guard !isRunningTests else { return }
        Telemetry.start()

        let controller = NotchWindowController()

        // `TOKNOTCH_DEMO=1` puts fixed numbers on screen for screenshots and
        // for eyeballing the layout without touching tokscale. For the README
        // and site shots, `TOKNOTCH_DEMO_LANGUAGE`, `TOKNOTCH_DEMO_EDGE` and
        // `TOKNOTCH_DEMO_HOVER` (a ring index) choose what is on screen.
        let environment = ProcessInfo.processInfo.environment
        if environment["TOKNOTCH_DEMO"] == "1" {
            let language = environment["TOKNOTCH_DEMO_LANGUAGE"]
                .flatMap(AppLanguage.init(rawValue:)) ?? .simplifiedChinese
            controller.model.rings = Fixtures.rings(language: language)
            if let edge = environment["TOKNOTCH_DEMO_EDGE"].flatMap(NotchEdge.init(rawValue:)) {
                controller.model.edge = edge
            }
            controller.show()
            if let hover = environment["TOKNOTCH_DEMO_HOVER"].flatMap(Int.init) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    controller.present(hovering: hover)
                }
            }
            notchController = controller
            return
        }

        // Before Preferences reads anything, or the first-launch flag and every
        // choice would be read from an empty domain.
        Preferences.migrateFromPreviousName()
        let preferences = Preferences()
        self.preferences = preferences
        preferences.addLoginItemOnce()

        let store = UsageStore()
        store.language = preferences.appLanguage
        store.enabledVendors = preferences.enabledVendors
        store.subscriptions = preferences.subscriptions
        self.store = store

        // The stored edge goes in before the panel is ever put up. The sink
        // below delivers on the next run loop turn, by which time the notch has
        // already been shown on the default edge — so without this, every launch
        // on any other edge opens with a flash of the right-hand one and then
        // crossfades away from it.
        controller.model.edge = preferences.notchEdge

        let updater = Updater()
        updater.start()
        self.updater = updater

        let settings = SettingsWindowController(preferences: preferences, store: store,
                                                updater: updater)
        controller.onOpenSettings = { [weak settings] in settings?.show() }
        self.settings = settings
        setupMainMenu()

        let whatsNew = WhatsNewWindowController(preferences: preferences,
                                                version: updater.currentVersion)
        self.whatsNew = whatsNew

        if preferences.isFirstLaunch {
            // A fresh install has nothing to be told has changed. It opens
            // straight on Payback, the page that says what the rings are for,
            // and this version counts as seen so What's New waits for the next.
            preferences.lastSeenVersion = updater.currentVersion
            Task { @MainActor [weak settings] in
                try? await Task.sleep(for: .milliseconds(600))
                settings?.show()
            }
        } else {
            whatsNew.showIfNeeded()
        }

        let about = AboutWindowController(preferences: preferences, version: updater.currentVersion)
        self.about = about
        settings.onAbout = { [weak about] in about?.show() }

        menuBar = MenuBarContext(
            preferences: preferences, store: store, updater: updater,
            openSettings: { [weak settings] in settings?.show() },
            about: { [weak about] in about?.show() }
        )

        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.reffwu.toknotch.openSettings"),
            object: nil, queue: .main
        ) { [weak settings] _ in settings?.show() }

        preferences.$showsInDock
            .receive(on: RunLoop.main)
            .sink { [weak settings] shows in
                let policy: NSApplication.ActivationPolicy = shows ? .regular : .accessory
                guard NSApp.activationPolicy() != policy else { return }
                NSApp.setActivationPolicy(policy)
                // Switching hands focus to whatever was behind, which would
                // bury the window the switch was just flipped in.
                if settings?.isVisible == true { settings?.show() }
            }
            .store(in: &cancellables)

        preferences.$notchVisibility
            .receive(on: RunLoop.main)
            .sink { [weak controller] in controller?.apply($0) }
            .store(in: &cancellables)

        preferences.$notchEdge
            .receive(on: RunLoop.main)
            .sink { [weak controller] in controller?.apply(edge: $0) }
            .store(in: &cancellables)

        // Both of these are presentation: the store re-renders the rings it
        // already has rather than reading tokscale again.
        preferences.$appLanguage
            .receive(on: RunLoop.main)
            .sink { [weak store] in store?.language = $0 }
            .store(in: &cancellables)

        preferences.$enabledVendors
            .receive(on: RunLoop.main)
            .sink { [weak store] in store?.enabledVendors = $0 }
            .store(in: &cancellables)

        preferences.$subscriptions
            .receive(on: RunLoop.main)
            .sink { [weak store] in store?.subscriptions = $0 }
            .store(in: &cancellables)

        // Finding a plan is itself the answer to "do you want this vendor's
        // ring": somebody paying for Claude every month wants to see Claude.
        // Once each, so switching one off keeps it off.
        store.$detectedPlans
            .receive(on: RunLoop.main)
            .sink { [weak preferences] plans in
                preferences?.autoEnableRings(for: plans.keys.sorted { $0.rawValue < $1.rawValue })
            }
            .store(in: &cancellables)

        store.$rings
            .receive(on: RunLoop.main)
            .sink { [weak controller] rings in
                withAnimation(NotchMotion.unfold) { controller?.model.rings = rings }
                controller?.model.now = Date()
            }
            .store(in: &cancellables)

        store.$isRefreshing
            .receive(on: RunLoop.main)
            .sink { [weak controller] in controller?.model.isRefreshing = $0 }
            .store(in: &cancellables)

        controller.onRefresh = { [weak store] in store?.refreshNow(byHand: true) }
        store.start()

        controller.show()
        notchController = controller
    }

    /// Closing the settings window must not take the app with it.
    ///
    /// The default for a Dock app is to quit once its last window closes, which
    /// here would kill the notch — the part that is actually the product —
    /// every time someone shut the settings they had just opened.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Launching the app again while it is already running lands here, so
    /// opening it from Applications or Spotlight reopens settings.
    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows: Bool) -> Bool {
        settings?.show()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        store?.stop()
        notchController?.stop()
    }

    @objc @MainActor func openSettingsFromMenu() {
        settings?.show()
    }

    @IBAction @MainActor func showSettingsWindow(_ sender: Any?) {
        settings?.show()
    }

    @IBAction @MainActor func showPreferencesWindow(_ sender: Any?) {
        settings?.show()
    }

    @MainActor private func setupMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu(title: "TokNotch")
        appMenuItem.submenu = appMenu
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit TokNotch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenu.addItem(quitItem)
        NSApp.mainMenu = mainMenu
    }
}
