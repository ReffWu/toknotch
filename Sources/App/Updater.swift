import Foundation

@MainActor
final class Updater: NSObject, ObservableObject {
    enum Outcome: Equatable {
        case idle
        case checking
        case upToDate(Date)
        case found(String)
        case unreachable
        case failed(String)

        var message: String? {
            switch self {
            case .idle: return nil
            case .checking: return "Checking…"
            case .upToDate: return "TokNotch is running locally."
            case .found(let version): return "TokNotch \(version) is available."
            case .unreachable: return "Couldn't reach the update feed — nothing is wrong with this copy."
            case .failed(let why): return "Couldn't check for updates — \(why)"
            }
        }
    }

    @Published private(set) var outcome: Outcome = .idle

    var automatic: Bool {
        get { false }
        set {}
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    var lastChecked: Date? { nil }

    func checkNow() {}
    func checkForUpdates() {}
    func start() {}
}
