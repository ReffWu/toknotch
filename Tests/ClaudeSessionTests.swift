import XCTest
@testable import Codenotch

final class ClaudeSessionRecordTests: XCTestCase {
    private func record(_ json: String) -> ClaudeSessionRecord? {
        let object = try! JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        return ClaudeSessionRecord(json: object)
    }

    private func session(_ json: String) -> AgentSession? { record(json)?.session }

    /// A real file, trimmed. Unknown keys must not cost us the session.
    func testDecodesALiveSession() throws {
        let s = try XCTUnwrap(session("""
        { "pid": 2678, "sessionId": "c85d4247", "cwd": "/Users/vinz/usage-notch",
          "startedAt": 1787894126697, "procStart": "Fri Aug 28 05:15:20 2026",
          "kind": "interactive", "entrypoint": "cli", "name": "usage-notch-bc",
          "status": "busy", "statusUpdatedAt": 1787897225305,
          "peerFeatures": ["notify_idle"], "somethingNew": 42 }
        """))
        XCTAssertEqual(s.id, "claude.2678")
        XCTAssertEqual(s.name, "usage-notch-bc")
        XCTAssertEqual(s.state, .busy)
        XCTAssertEqual(s.detail, "Terminal · usage-notch")
    }

    func testWaitingCarriesWhatItIsWaitingFor() throws {
        let s = try XCTUnwrap(session("""
        { "pid": 1, "cwd": "/tmp/x", "status": "waiting", "waitingFor": "permission" }
        """))
        XCTAssertEqual(s.state, .waiting)
        XCTAssertEqual(s.waitingFor, "permission")
    }

    /// `tempo` is the normalised form and outranks the raw status word.
    func testTempoWins() throws {
        XCTAssertEqual(try XCTUnwrap(session("""
        { "pid": 1, "cwd": "/tmp/x", "status": "busy", "tempo": "blocked" }
        """)).state, .waiting)
        XCTAssertEqual(try XCTUnwrap(session("""
        { "pid": 1, "cwd": "/tmp/x", "status": "idle", "tempo": "active" }
        """)).state, .busy)
    }

    func testUnknownStatusIsTreatedAsIdle() throws {
        XCTAssertEqual(try XCTUnwrap(session("""
        { "pid": 1, "cwd": "/tmp/x", "status": "hibernating" }
        """)).state, .idle)
    }

    func testFallsBackToTheFolderWhenUnnamed() throws {
        XCTAssertEqual(try XCTUnwrap(session("""
        { "pid": 1, "cwd": "/Users/vinz/notch-app", "status": "idle" }
        """)).name, "notch-app")
    }

    func testRejectsRecordsWithoutAPidOrCwd() {
        XCTAssertNil(session(#"{ "cwd": "/tmp/x", "status": "busy" }"#))
        XCTAssertNil(session(#"{ "pid": 1, "status": "busy" }"#))
    }

    func testSurfaceNamesWhereItIsRunning() throws {
        func surface(_ entrypoint: String) throws -> String {
            ClaudeSessionRecord.surface(entrypoint)
        }
        XCTAssertEqual(try surface("claude-vscode"), "VS Code")
        XCTAssertEqual(try surface("claude-desktop"), "Desktop")
        XCTAssertEqual(try surface("cli"), "Terminal")
    }

    /// `procStart` is a ctime string in UTC. Reading it as local time puts it
    /// hours out, and the liveness check then throws away a live session — which
    /// is exactly what happened the first time this was wired up.
    func testProcStartIsParsedAsUTC() throws {
        let parsed = try XCTUnwrap(ClaudeSessionRecord.parseProcStart("Fri Aug 28 05:15:20 2026"))
        XCTAssertEqual(parsed.timeIntervalSince1970, 1787894120, accuracy: 1)
    }

    func testProcStartHandlesASpacePaddedDay() throws {
        let parsed = try XCTUnwrap(ClaudeSessionRecord.parseProcStart("Sat Aug  8 05:15:20 2026"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(calendar.component(.day, from: parsed), 8)
    }

    /// The epoch field is unambiguous, so it wins over the ctime string.
    func testPrefersTheEpochStartTime() throws {
        let r = try XCTUnwrap(record("""
        { "pid": 1, "cwd": "/tmp/x", "status": "busy",
          "startedAt": 1787894126697, "procStart": "Mon Jan 1 00:00:00 2001" }
        """))
        XCTAssertEqual(try XCTUnwrap(r.startedAt).timeIntervalSince1970, 1787894126.697, accuracy: 0.01)
    }
}
