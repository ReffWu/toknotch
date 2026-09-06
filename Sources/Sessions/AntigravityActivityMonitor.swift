import Combine
import Foundation

/// Notices when Antigravity is working.
///
/// Its transcripts are appended to as an agent runs, so a file written moments
/// ago is a turn in progress. The step *statuses* cannot be used for this —
/// every one of them says `DONE`, because a step is only written once it is
/// finished. Recency is the signal there is.
///
/// Without this the Gemini ring never showed the working state that Claude,
/// Cursor and Codex all had, and the store never learned Antigravity was busy,
/// so it stayed on its slow idle poll while usage was actively being spent.
final class AntigravityActivityMonitor: AgentActivityMonitor {
    @Published private(set) var sessions: [AgentSession] = []
    var sessionsPublisher: AnyPublisher<[AgentSession], Never> { $sessions.eraseToAnyPublisher() }

    private let root: URL
    private let interval: TimeInterval
    /// How recently a transcript must have been written to count as live.
    /// Generous, because a model can think for a while between two lines.
    private let staleAfter: TimeInterval
    private var timer: Timer?

    init(root: URL = AntigravityActivity.transcriptRoot,
         interval: TimeInterval = 2,
         staleAfter: TimeInterval = 45) {
        self.root = root
        self.interval = interval
        self.staleAfter = staleAfter
    }

    func start() {
        stop()
        poll()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let found = Self.read(root: root, staleAfter: staleAfter)
        guard found != sessions else { return }
        sessions = found
    }

    static func read(root: URL, staleAfter: TimeInterval, now: Date = Date()) -> [AgentSession] {
        let manager = FileManager.default
        guard let trajectories = try? manager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil
        ) else { return [] }

        var newest: (url: URL, modified: Date)?
        for trajectory in trajectories {
            let transcript = trajectory
                .appendingPathComponent(".system_generated/logs/transcript.jsonl")
            guard let modified = (try? manager.attributesOfItem(atPath: transcript.path))?[.modificationDate] as? Date
            else { continue }
            if newest == nil || modified > newest!.modified {
                newest = (transcript, modified)
            }
        }

        guard let newest, let session = session(trajectory: newest.url,
                                                modified: newest.modified,
                                                staleAfter: staleAfter, now: now)
        else { return [] }
        return [session]
    }

    /// Only a transcript written within the window counts. An older one is a
    /// finished turn, and showing it as work in progress would be a guess
    /// dressed as a fact.
    static func session(
        trajectory: URL, modified: Date, staleAfter: TimeInterval, now: Date
    ) -> AgentSession? {
        guard now.timeIntervalSince(modified) <= staleAfter else { return nil }
        // The trajectory's own directory names it; the file is always
        // `transcript.jsonl`.
        let id = trajectory.deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
        return AgentSession(
            id: "antigravity.\(id)",
            name: "Antigravity",
            detail: "Working",
            state: .busy,
            waitingFor: nil,
            since: modified
        )
    }
}
