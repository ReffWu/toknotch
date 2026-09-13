import Foundation
import Sparkle

/// Checking for, and installing, new versions.
///
/// Wraps Sparkle rather than exposing it: the settings screen needs two
/// things — a state to describe and a button — and everything else Sparkle
/// offers would only be a way to get the update flow wrong. Checking runs on
/// its own schedule, always: an app nobody updates is an app that quietly
/// stops matching the tools it reads.
@MainActor
final class Updater: NSObject, ObservableObject {
    enum Outcome: Equatable {
        case idle
        case checking
        case upToDate(Date)
        case found(String)
        case unreachable
        case failed(String)
        /// This build has no update feed, which is the normal state of one
        /// built locally. Deliberately not an error: there is nothing wrong
        /// with this copy, it simply was not published.
        case unconfigured
    }

    @Published private(set) var outcome: Outcome = .idle

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    var lastChecked: Date? { controller?.updater.lastUpdateCheckDate }

    /// Whether this build can receive updates at all.
    ///
    /// A development build has neither a feed nor a public key, and starting
    /// Sparkle without them produces a stream of errors nobody can act on — so
    /// it is not started. Publishing fills both in and this becomes true with
    /// no code change.
    static var isConfigured: Bool {
        let info = Bundle.main.infoDictionary ?? [:]
        let feed = info["SUFeedURL"] as? String ?? ""
        let key = info["SUPublicEDKey"] as? String ?? ""
        return !feed.isEmpty && !key.isEmpty
    }

    private var controller: SPUStandardUpdaterController?

    /// Starts checking. Call once, at launch.
    func start() {
        guard Self.isConfigured else {
            outcome = .unconfigured
            return
        }
        // `startingUpdater: true` schedules the background check Sparkle is
        // for; the user driver is what puts its dialogue on screen.
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: self,
                                                  userDriverDelegate: nil)
        controller?.updater.automaticallyChecksForUpdates = true
    }

    /// The Check Now button. Shows Sparkle's own dialogue, which is the part
    /// that has been through everybody else's edge cases.
    func checkForUpdates() {
        guard let controller else {
            outcome = .unconfigured
            return
        }
        outcome = .checking
        controller.updater.checkForUpdates()
    }
}

// MARK: - Sparkle's side

extension Updater: SPUUpdaterDelegate {
    nonisolated func updater(_ updater: SPUUpdater,
                             didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        Task { @MainActor in self.outcome = .found(version) }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Task { @MainActor in self.outcome = .upToDate(Date()) }
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let code = (error as NSError).code
        // Cancelling is not a failure, and neither is "nothing to do".
        guard code != Int(Sparkle.SUError.noUpdateError.rawValue),
              code != Int(Sparkle.SUError.installationCanceledError.rawValue)
        else { return }

        let unreachable = (error as NSError).domain == NSURLErrorDomain
        let message = error.localizedDescription
        Task { @MainActor in
            self.outcome = unreachable ? .unreachable : .failed(message)
        }
    }
}
