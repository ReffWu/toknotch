import Combine

/// Anything that can say what an agent is doing right now.
@MainActor
protocol AgentActivityMonitor: AnyObject {
    var sessions: [AgentSession] { get }
    var sessionsPublisher: AnyPublisher<[AgentSession], Never> { get }
    func start()
    func stop()
}
