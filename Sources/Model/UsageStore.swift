import AppKit
import Combine
import os

/// Reads tokscale on a timer and publishes the rings.
///
/// There is deliberately no archive here. The old store kept the last good
/// reading on disk because its numbers came from vendor APIs that could be
/// down, rate-limited or signed out; these come from a local command that
/// answers in under a second, so a cache would buy nothing and could only ever
/// show something staler than simply asking again.
@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var rings: [RingSnapshot] = []
    /// A read in flight, so the rings can show it happening.
    @Published private(set) var isRefreshing = false
    /// Vendors this machine has actually used, busiest first — the settings
    /// list is built from this, so a ring is only offered for a company whose
    /// models have really been run.
    @Published private(set) var availableVendors: [Vendor] = []
    /// When the numbers on screen were read. Nil until the first read lands.
    @Published private(set) var lastUpdated: Date?
    /// What went wrong with the most recent read, in the reader's language.
    /// Cleared as soon as one succeeds.
    @Published private(set) var problem: String?
    /// Plans found in the tools' own configuration files. Nothing here was
    /// typed by anybody, and nothing here came from a credential store.
    @Published private(set) var detectedPlans: [Vendor: DetectedPlan] = [:]

    /// Presentation, not data. Changing either re-renders from the digest we
    /// already have rather than shelling out again.
    var language: AppLanguage = .system { didSet { guard language != oldValue else { return }; render() } }
    var enabledVendors: Set<Vendor> = [] { didSet { guard enabledVendors != oldValue else { return }; render() } }
    /// The user's own answers, which override anything detected. A vendor with
    /// an entry of zero here is somebody saying "no plan", which is different
    /// from having said nothing.
    var subscriptions: [Vendor: Subscription] = [:] { didSet { guard subscriptions != oldValue else { return }; render() } }

    /// What the payback figures actually use: what was found, with whatever the
    /// user has said about it laid over the top.
    var effectivePlans: [Vendor: Subscription] {
        var merged = detectedPlans.compactMapValues(\.subscription)
        merged.merge(subscriptions) { _, override in override }
        return merged.filter { $0.value.isActive }
    }

    /// Whether this vendor's figures came from its own configuration rather
    /// than from the user.
    func isDetected(_ vendor: Vendor) -> Bool {
        subscriptions[vendor] == nil && detectedPlans[vendor]?.subscription != nil
    }

    private var digest: UsageDigest?
    private var failure: String?
    private let interval: TimeInterval
    private var timer: Timer?
    private var task: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
    /// When Antigravity's usage was last copied into tokscale's cache.
    private var lastAntigravitySync: Date?
    /// A sync takes several seconds of CPU, so it runs at most this often,
    /// plus whenever somebody asks for a refresh by hand.
    private static let antigravitySyncInterval: TimeInterval = 5 * 60

    init(interval: TimeInterval = 60) {
        self.interval = interval
        detectedPlans = PlanDetector.detect()
        render()
    }

    func start() {
        refreshNow()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshNow() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        // Waking is the one moment the numbers are guaranteed to have moved on
        // without us.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshNow() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        task?.cancel()
        task = nil
        if let wakeObserver {
            // Block-based observers are not removed by `removeObserver(self)`.
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
    }

    /// Seed a digest without shelling out, for tests and previews.
    func loadForTesting(_ digest: UsageDigest) {
        self.digest = digest
        self.availableVendors = digest.vendors.map(\.vendor)
        self.lastUpdated = digest.generatedAt
        render()
    }

    func refreshNow(byHand: Bool = false) {
        guard task == nil else { return }
        isRefreshing = true
        task = Task { [weak self] in
            await self?.syncAntigravityIfDue(force: byHand)
            await self?.refresh()
            self?.task = nil
            self?.isRefreshing = false
        }
    }

    /// Only on a Mac that has Antigravity. A failed sync is logged and
    /// otherwise ignored: the other tools' numbers must not wait on it.
    private func syncAntigravityIfDue(force: Bool) async {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.antigravity") != nil
        else { return }
        if !force, let last = lastAntigravitySync,
           Date().timeIntervalSince(last) < Self.antigravitySyncInterval { return }
        lastAntigravitySync = Date()
        do {
            try await TokscaleCLI.syncAntigravity()
        } catch {
            Log.usage.error("antigravity sync failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func refresh() async {
        do {
            // Two independent commands; run together they cost about as long as
            // the slower one.
            async let graph = TokscaleCLI.graph()
            async let lifetime = TokscaleCLI.lifetime()
            let digest = UsageDigest.build(graph: try await graph, lifetime: try await lifetime)

            self.digest = digest
            self.failure = nil
            self.problem = nil
            self.lastUpdated = digest.generatedAt
            self.availableVendors = digest.vendors.map(\.vendor)
            // Re-read on each refresh: a plan changed in another app should
            // show up here without restarting.
            self.detectedPlans = PlanDetector.detect()
            // Notice rather than debug: this is the app's health signal, and
            // debug records are not kept, so the one line worth having when
            // somebody asks why the rings are empty was never there to read.
            Log.usage.notice("""
                read ok — lifetime \(digest.lifetime.totals.tokens, privacy: .public),                 today \(digest.today.totals.tokens, privacy: .public),                 \(digest.vendors.count, privacy: .public) vendor(s)
                """)
        } catch {
            // The last good digest stays on screen. A failed read is a fact
            // about this attempt, not about the numbers already shown.
            self.failure = Self.explain(error, language: language)
            self.problem = self.failure
            Log.usage.error("tokscale read failed: \(String(describing: error), privacy: .public)")
        }
        render()
    }

    /// What a plan is currently returning, so the settings screen can show the
    /// answer while the figures are still being typed rather than making
    /// somebody close it and hover a ring to find out.
    /// The plan in force for a vendor, detected or overridden.
    func plan(for vendor: Vendor) -> Subscription? { effectivePlans[vendor] }

    func payback(for vendor: Vendor, plan: Subscription,
                 now: Date = Date(), calendar: Calendar = .current) -> Payback? {
        guard let digest, plan.isActive else { return nil }
        let period = BillingPeriod.current(renewalDay: plan.renewalDay,
                                           now: now, calendar: calendar)
        return Payback(subscription: plan, period: period,
                       earned: digest.totals(for: vendor, in: period, calendar: calendar).cost)
    }

    /// Every plan in force, added up over each one's own current period: what
    /// they cost together and what the same usage would have cost at API
    /// prices. Nil while no plan is set, so callers can say so instead of
    /// showing a zero.
    func periodPayback() -> (paid: Double, earned: Double)? {
        let plans = effectivePlans
        guard !plans.isEmpty else { return nil }
        return plans.reduce((paid: 0, earned: 0)) { sum, entry in
            (sum.paid + entry.value.monthlyUSD,
             sum.earned + (payback(for: entry.key, plan: entry.value)?.earned ?? 0))
        }
    }

    /// One vendor's lifetime totals, for the settings list to show what each
    /// row is actually about.
    func lifetime(for vendor: Vendor) -> UsageDigest.Totals? {
        digest?.vendors.first { $0.vendor == vendor }?.totals
    }

    /// Rebuild the rings from whatever we know. Cheap, and the only place
    /// `rings` is written.
    private func render() {
        guard let digest else {
            let note = failure
            rings = RingKind.primaries.map {
                RingBuilder.placeholder($0, language: language, note: note)
            }
            return
        }
        rings = RingBuilder.rings(from: digest, vendors: enabledVendors,
                                  subscriptions: effectivePlans, language: language)
    }

    /// Says what went wrong *and* what fixes it. "HTTP 500" for a local command
    /// that is simply not installed sends people to look in the wrong place.
    private static func explain(_ error: Error, language: AppLanguage) -> String {
        guard let failure = error as? TokscaleCLI.Failure else {
            return language.t("status.readFailed", (error as NSError).localizedDescription)
        }
        switch failure {
        case .notInstalled:
            return language.t("status.notInstalled")
        case .exited(127):
            // tokscale is a `#!/usr/bin/env node` script when it is not the
            // bundled binary, so this means node is somewhere we did not look.
            return language.t("status.noNode")
        case .exited(let code):
            return language.t("status.exited", code)
        case .undecodable:
            return language.t("status.undecodable")
        case .timedOut:
            return language.t("status.timedOut")
        }
    }
}
