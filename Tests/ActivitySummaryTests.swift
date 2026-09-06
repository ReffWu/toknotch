import SQLite3
import XCTest
@testable import Codenotch

final class ActivitySummaryTests: XCTestCase {
    private func session(_ state: AgentSession.State, name: String = "s") -> AgentSession {
        AgentSession(id: name, name: name, detail: "Terminal · \(name)",
                     state: state, waitingFor: nil, since: Date())
    }

    func testNothingRunningMeansNoCell() {
        XCTAssertNil(ActivitySummary(sessions: []))
    }

    /// Blocked outranks busy: it is the only state that is asking you for
    /// something, so it must not be hidden behind a session that is merely busy.
    func testWaitingOutranksWorking() {
        let summary = ActivitySummary(sessions: [session(.busy), session(.waiting), session(.idle)])
        XCTAssertEqual(summary?.state, .waiting)
        XCTAssertEqual(summary?.label, "waiting")
    }

    func testWorkingOutranksIdle() {
        XCTAssertEqual(ActivitySummary(sessions: [session(.idle), session(.busy)])?.state, .working)
    }

    func testAllIdleReadsAsIdle() {
        XCTAssertEqual(ActivitySummary(sessions: [session(.idle), session(.idle)])?.state, .idle)
    }

    /// Working must not borrow a colour from the usage scale — the indicator
    /// sits inside a ring whose colour already means something else.
    func testWorkingIsNeutralAndWaitingIsNot() {
        XCTAssertEqual(ActivitySummary(sessions: [session(.busy)])?.color, Palette.textPrimary)
        XCTAssertEqual(ActivitySummary(sessions: [session(.waiting)])?.color, Palette.watch)
    }
}

/// The instant every fixture's `unfinishedRunAt` names. At file scope so it can
/// serve as a default argument, which a stored property cannot.
private let runAt = Date(timeIntervalSince1970: 1787981829.823)

/// Cursor publishes no session registry, so its working state is read out of the
/// editor's `composerHeaders` rows. These pin what counts as working.
@MainActor
final class CursorActivityTests: XCTestCase {
    /// Cursor writes its timestamps as milliseconds since the epoch.
    private func millis(_ date: Date) -> NSNumber {
        NSNumber(value: (date.timeIntervalSince1970 * 1000).rounded())
    }

    /// One `composerHeaders` row. Built rather than pasted so a fixture differs
    /// from its neighbour only where the test means it to, and so the epoch
    /// literal exists once instead of once per test.
    private func header(id: String? = "abc",
                        run: Date? = runAt,
                        checkpoint: Date? = nil,
                        lastUpdated: Date? = nil,
                        created: Date? = nil,
                        name: String? = nil,
                        subtitle: String? = nil,
                        blocking: Bool? = nil,
                        plan: Bool? = nil) -> String {
        var head: [String: Any] = [:]
        head["composerId"] = id
        head["unfinishedRunAt"] = run.map(millis)
        head["conversationCheckpointLastUpdatedAt"] = checkpoint.map(millis)
        head["lastUpdatedAt"] = lastUpdated.map(millis)
        head["createdAt"] = created.map(millis)
        head["name"] = name
        head["subtitle"] = subtitle
        head["hasBlockingPendingActions"] = blocking
        head["hasPendingPlan"] = plan
        let data = try! JSONSerialization.data(withJSONObject: head)
        return String(data: data, encoding: .utf8)!
    }

    /// `launchedAt: .distantPast` stands for "Cursor is running and has been
    /// for longer than any row in the fixture" — the ordinary case. `now`
    /// defaults to a second after the run started, since a fixture read against
    /// the wall clock would be hours stale and never busy.
    private func session(_ json: String,
                         launchedAt: Date? = .distantPast,
                         staleAfter: TimeInterval = 15 * 60,
                         now: Date? = nil) -> AgentSession? {
        CursorActivityMonitor.session(fromHeader: json,
                                      cursorLaunchedAt: launchedAt,
                                      staleAfter: staleAfter,
                                      now: now ?? runAt.addingTimeInterval(1))
    }

    /// The bug this exists to stop: Cursor is killed mid-run, `unfinishedRunAt`
    /// is never cleared, and the notch reports three agents working a day later
    /// with the editor not even open.
    func testARunIsNotBusyWhenCursorIsNotRunning() {
        XCTAssertNil(session(header(), launchedAt: nil))
    }

    /// Same row, same absent editor, but Cursor has since been restarted: the
    /// run belongs to the process that is gone, not the one now open.
    func testARunFromBeforeThisLaunchIsNotBusy() {
        XCTAssertNil(session(header(), launchedAt: runAt.addingTimeInterval(1)))
    }

    func testARunStartedAfterThisLaunchIsBusy() throws {
        let s = try XCTUnwrap(session(header(), launchedAt: runAt.addingTimeInterval(-1)))
        XCTAssertEqual(s.state, .busy)
    }

    /// The one process liveness cannot see: a run abandoned with the editor
    /// still open. `unfinishedRunAt` stays set for ever, so the only thing that
    /// says the run is over is a checkpoint that stopped moving.
    func testARunWhoseCheckpointWentSilentIsNotBusy() {
        XCTAssertNil(session(header(checkpoint: runAt.addingTimeInterval(160)),
                             now: runAt.addingTimeInterval(3600)))
    }

    /// The other side of it: an agent between tool calls is quiet for seconds,
    /// not hours, and must keep its spinner.
    func testARunStillWritingIsBusy() throws {
        let s = try XCTUnwrap(session(header(checkpoint: runAt.addingTimeInterval(160)),
                                      now: runAt.addingTimeInterval(200)))
        XCTAssertEqual(s.state, .busy)
    }

    /// A blocked row still counts with the editor shut — it really is waiting
    /// on you — but it must not be dated by a run that never finished.
    func testWaitingSurvivesAClosedEditorButNotAStaleRunTime() throws {
        let checkpoint = runAt.addingTimeInterval(18_170)
        let s = try XCTUnwrap(session(header(checkpoint: checkpoint, plan: true),
                                      launchedAt: nil))
        XCTAssertEqual(s.state, .waiting)
        XCTAssertEqual(s.since, checkpoint)
    }

    /// `unfinishedRunAt` is the composer's creation time, not the current run's:
    /// a chat with two turns seven minutes apart, killed during the second,
    /// still reports the first. So a chat opened long before Cursor last started
    /// and working right now must still spin — gating on that field would have
    /// silently retired every conversation older than the current launch.
    func testAnOldChatWritingRightNowIsBusy() throws {
        let checkpoint = runAt.addingTimeInterval(18_170)
        let s = try XCTUnwrap(session(header(checkpoint: checkpoint),
                                      launchedAt: runAt.addingTimeInterval(8_170),
                                      now: checkpoint.addingTimeInterval(60)))
        XCTAssertEqual(s.state, .busy)
    }

    /// The restart case, read off the timestamp that actually moves: a
    /// conversation last written to before this Cursor started belongs to the
    /// process that is gone.
    func testAConversationLastWrittenBeforeThisLaunchIsNotBusy() {
        XCTAssertNil(session(header(checkpoint: runAt.addingTimeInterval(160)),
                             launchedAt: runAt.addingTimeInterval(8_170),
                             now: runAt.addingTimeInterval(8_230)))
    }

    /// The boundary: a conversation written at the very instant Cursor launched
    /// is the current process's, not the dead one's.
    func testAWriteAtTheLaunchInstantCountsAsThisProcess() throws {
        let s = try XCTUnwrap(session(header(checkpoint: runAt), launchedAt: runAt))
        XCTAssertEqual(s.state, .busy)
    }

    /// A quarter of real rows carry `lastUpdatedAt` and no checkpoint. Dropping
    /// it from the chain dated them from `createdAt` instead — a chat blocked
    /// ten minutes ago reading as blocked for weeks.
    func testLastUpdatedAtStandsInForAMissingCheckpoint() throws {
        let touched = runAt.addingTimeInterval(18_170)
        let s = try XCTUnwrap(session(header(run: nil, lastUpdated: touched,
                                             created: runAt.addingTimeInterval(-981_829),
                                             plan: true),
                                      launchedAt: nil))
        XCTAssertEqual(s.state, .waiting)
        XCTAssertEqual(s.since, touched)
    }

    /// The last rung. A row blocked with nothing written to it since it was
    /// opened is dated from when it was opened — not from the wall clock, which
    /// would restamp it on every two-second poll and republish for ever.
    func testAWaitingRowWithNoWritesFallsBackToCreatedAt() throws {
        let created = runAt.addingTimeInterval(-981_829)
        let s = try XCTUnwrap(session(header(run: nil, created: created, plan: true),
                                      launchedAt: nil))
        XCTAssertEqual(s.since, created)
    }

    /// `launchDate` is usually absent — of 123 running applications on the
    /// machine this was written on, 105 had none, Finder and Chrome among them.
    /// Reporting that as "Cursor is closed" would silently retire every Cursor
    /// row while the editor sat there working.
    func testARunningCursorWithNoLaunchDateIsStillRunning() {
        XCTAssertEqual(CursorActivityMonitor.launchDate(found: true, launchDate: nil),
                       .distantPast)
        XCTAssertNil(CursorActivityMonitor.launchDate(found: false, launchDate: nil))
    }

    /// The window is a boundary, and it is inclusive — the siblings' is too.
    func testTheStalenessBoundaryIsInclusive() throws {
        let fixture = header(checkpoint: runAt)
        let atTheEdge = try XCTUnwrap(session(fixture, staleAfter: 60,
                                              now: runAt.addingTimeInterval(60)))
        XCTAssertEqual(atTheEdge.state, .busy)
        XCTAssertNil(session(fixture, staleAfter: 60, now: runAt.addingTimeInterval(61)))
    }

    /// `unfinishedRunAt` is set while a run is in flight and cleared when it ends.
    func testAnUnfinishedRunIsBusy() throws {
        let s = try XCTUnwrap(session(header(name: "General chat",
                                             subtitle: "Read SKILL.md", blocking: false)))
        XCTAssertEqual(s.state, .busy)
        XCTAssertEqual(s.name, "General chat")
        XCTAssertEqual(s.detail, "Read SKILL.md")
    }

    /// A finished run is not a session worth a row — an editor with a long chat
    /// history is not a pile of things happening.
    func testAFinishedRunIsNotListed() {
        XCTAssertNil(session(header(run: nil, blocking: false)))
    }

    /// Blocked outranks busy: it is the only state asking for something.
    func testBlockingActionsOutrankARunningTurn() throws {
        let s = try XCTUnwrap(session(header(blocking: true)))
        XCTAssertEqual(s.state, .waiting)
        XCTAssertEqual(s.waitingFor, "needs your input")
    }

    func testAPendingPlanAlsoCountsAsWaiting() throws {
        XCTAssertEqual(try XCTUnwrap(session(header(run: nil, plan: true))).state, .waiting)
    }

    /// Ids are namespaced, so a Cursor composer can never collide with a Claude pid.
    func testIdsAreNamespaced() throws {
        XCTAssertEqual(try XCTUnwrap(session(header())).id, "cursor.abc")
    }

    func testRejectsRubbish() {
        XCTAssertNil(session("not json"))
        XCTAssertNil(session(header(id: nil)))
    }

    // MARK: - The store read

    /// Rows land newest-first, and an archived chat is not something happening —
    /// both are in the SQL rather than in Swift, so only a real store shows them.
    func testReadOrdersNewestFirstAndSkipsArchivedRows() throws {
        let older = runAt
        let newer = runAt.addingTimeInterval(100)
        let url = try makeStore([
            (header(id: "older", run: older, checkpoint: older), archived: 0),
            (header(id: "newer", run: newer, checkpoint: newer), archived: 0),
            (header(id: "filed", run: newer, checkpoint: newer), archived: 1),
        ])
        defer { try? FileManager.default.removeItem(at: url) }

        let found = CursorActivityMonitor.read(store: url, cursorLaunchedAt: .distantPast,
                                               staleAfter: 10 * 60,
                                               now: newer.addingTimeInterval(1))
        XCTAssertEqual(found.map(\.id), ["cursor.newer", "cursor.older"])
    }

    /// Mirrors `SQLiteStoreTests.makeDatabase`: closing checkpoints the WAL, so
    /// the file reads back the way it would after the editor has quit.
    private func makeStore(_ rows: [(String, archived: Int)]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cursor-\(UUID().uuidString).sqlite")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
        sqlite3_exec(db, """
        CREATE TABLE composerHeaders (value TEXT, isArchived INT, recency INT);
        """, nil, nil, nil)
        for (index, row) in rows.enumerated() {
            let escaped = row.0.replacingOccurrences(of: "'", with: "''")
            sqlite3_exec(db, """
            INSERT INTO composerHeaders VALUES ('\(escaped)', \(row.archived), \(index));
            """, nil, nil, nil)
        }
        sqlite3_close(db)
        return url
    }
}
