import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notchController: NotchWindowController?
    private var store: UsageStore?
    private var preferences: Preferences?
    private var settings: SettingsWindowController?
    private var whatsNew: WhatsNewWindowController?
    /// Held for the life of the app: releasing it stops the scheduled checks.
    private var updater: Updater?
    private var statusItem: StatusItemController?
    private var cancellables = Set<AnyCancellable>()

    /// The unit bundle is hosted by this app, so `xcodebuild test` launches it
    /// for real. Without this guard every test run put a live request on the
    /// usage endpoint — which is both wrong on its own terms and, on an endpoint
    /// that rate-limits, actively harmful.
    private var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set here, not in the Info.plist: this call is applied at launch and
        // overrides `LSUIElement` either way. Removing the plist key alone left
        // the app registered as a UIElement with no Dock tile, which looked
        // exactly like the icon having failed to install. The user's choice
        // replaces this a moment later, once preferences exist.
        NSApp.setActivationPolicy(.regular)
        guard !isRunningTests else { return }

        let controller = NotchWindowController()

        // `TOKNOTCH_DEMO=1` puts fixed numbers on screen for screenshots and
        // for eyeballing the layout without touching tokscale.
        if ProcessInfo.processInfo.environment["TOKNOTCH_DEMO"] == "1" {
            controller.model.rings = Fixtures.rings()
            controller.show()
            notchController = controller
            return
        }

        // Before Preferences reads anything, or the first-launch flag and every
        // choice would be read from an empty domain.
        Preferences.migrateFromPreviousName()
        let preferences = Preferences()
        self.preferences = preferences

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

        // What changed, once per version — including on a fresh install, where
        // it is the introduction.
        let whatsNew = WhatsNewWindowController(preferences: preferences,
                                                version: updater.currentVersion)
        self.whatsNew = whatsNew

        // With no dock icon and no window, a fresh install shows three rings on
        // a screen edge and no reason to look at them. Once, on the very first
        // run, it opens the one place that explains them.
        //
        // Sequenced behind What's New rather than beside it: two windows
        // arriving together is one to dismiss before you can read either.
        let introduce = { [weak settings] in
            guard preferences.isFirstLaunch else { return }
            settings?.show()
        }
        whatsNew.onDismiss = introduce
        if !whatsNew.showIfNeeded() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: introduce)
        }

        let statusItem = StatusItemController { [weak settings] in settings?.show() }
        self.statusItem = statusItem

        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.reff.toknotch.openSettings"),
            object: nil, queue: .main
        ) { [weak settings] _ in settings?.show() }

        preferences.$appPresence
            .receive(on: RunLoop.main)
            .sink { presence in
                NSApp.setActivationPolicy(presence.activationPolicy)
                if presence.wantsStatusItem { statusItem.show() } else { statusItem.hide() }
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

        controller.onRefresh = { [weak store] in store?.refreshNow() }
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

    /// The way back in when the notch is hidden.
    ///
    /// With no dock icon, no menu bar item and no notch on screen, there is
    /// otherwise nothing left to click — choosing Hide would be a one-way door.
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
