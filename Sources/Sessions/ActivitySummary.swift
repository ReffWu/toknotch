import SwiftUI

/// What the activity cell shows: the state of every live session, reduced to
/// the one thing worth knowing at a glance.
struct ActivitySummary: Equatable {
    enum State: Equatable {
        case working
        case waiting
        case idle
    }

    let state: State
    let sessions: [AgentSession]

    /// Nil when nothing is running — the cell disappears rather than sitting
    /// there saying nothing.
    init?(sessions: [AgentSession]) {
        guard !sessions.isEmpty else { return nil }
        self.sessions = sessions
        // Anything blocked on you outranks anything merely busy: it is the only
        // state where the notch is asking for something.
        if sessions.contains(where: { $0.state == .waiting }) {
            state = .waiting
        } else if sessions.contains(where: { $0.state == .busy }) {
            state = .working
        } else {
            state = .idle
        }
    }

    /// One short word, for the tooltip.
    var label: String {
        switch state {
        case .working: return "working"
        case .waiting: return "waiting"
        case .idle:    return "idle"
        }
    }

    /// White for working, deliberately: the indicator sits inside a ring whose
    /// colour already means "how much of your limit is gone", and a neutral
    /// tone cannot be misread as part of that scale. Waiting gets amber because
    /// it is the one state that wants something from you.
    var color: Color {
        switch state {
        case .working: return Palette.textPrimary
        case .waiting: return Palette.watch
        case .idle:    return Palette.ringTrack
        }
    }

    var waitingSessions: [AgentSession] { sessions.filter { $0.state == .waiting } }
}
