import XCTest
@testable import TokNotch

/// The shared-folder reports: what goes in, what comes out, and how two
/// devices' day buckets line up when they keep different time zones.
final class DeviceSyncTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeviceSync-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Fixtures

    private func counts(_ total: Int64) -> TokenCounts {
        TokenCounts(input: total, output: 0, cacheRead: 0, cacheWrite: 0, reasoning: 0)
    }

    private func graph(day: String, tokens: Int64, model: String = "claude-sonnet-5",
                       cost: Double = 1) -> GraphReport {
        GraphReport(contributions: [
            GraphReport.Day(date: day, tokenBreakdown: counts(tokens),
                            clients: [GraphReport.Day.Line(modelId: model,
                                                           tokens: counts(tokens),
                                                           cost: cost, messages: 1)],
                            cost: cost, messages: 1)
        ])
    }

    private func lifetime(model: String, tokens: Int64) -> UsageReport {
        UsageReport(entries: [UsageReport.Entry(model: model, tokens: counts(tokens),
                                                cost: 2, messages: 3)],
                    messages: 3)
    }

    private func report(deviceId: String, day: String, tokens: Int64,
                        offsetMinutes: Int = 0) -> DeviceReport {
        var report = DeviceReport(graph: graph(day: day, tokens: tokens),
                                  lifetime: lifetime(model: "claude-sonnet-5",
                                                     tokens: tokens),
                                  deviceId: deviceId, name: deviceId)
        report.utcOffsetMinutes = offsetMinutes
        return report
    }

    // MARK: - Round trip

    func testAReportSurvivesTheFolder() throws {
        let original = report(deviceId: "mac-a", day: "2026-11-12", tokens: 5000)
        XCTAssertTrue(DeviceSync.publish(original, in: directory))

        let peers = DeviceSync.peers(in: directory, excluding: "mac-b")
        XCTAssertEqual(peers.count, 1)
        // ISO-8601 keeps whole seconds, so the timestamp is the one field
        // that does not survive the round trip exactly.
        var expected = original
        expected.generatedAt = peers[0].generatedAt
        XCTAssertEqual(peers, [expected])
    }

    func testPeersNeverIncludeTheReaderItself() throws {
        // A file whose name does not match its owner is still excluded: the
        // check is on the report's own id, not just the file name.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let renamed = report(deviceId: "mac-a", day: "2026-11-12", tokens: 1)
        try encoder.encode(renamed)
            .write(to: directory.appendingPathComponent("mac-c.json"))

        XCTAssertTrue(DeviceSync.peers(in: directory, excluding: "mac-a").isEmpty)
        XCTAssertEqual(DeviceSync.peers(in: directory, excluding: "mac-b").count, 1)
    }

    func testAnUnreadableFileIsSkippedNotFatal() throws {
        DeviceSync.publish(report(deviceId: "mac-a", day: "2026-11-12", tokens: 1),
                           in: directory)
        try "not json".write(to: directory.appendingPathComponent("broken.json"),
                             atomically: true, encoding: .utf8)
        XCTAssertEqual(DeviceSync.peers(in: directory, excluding: "mac-b").count, 1)
    }

    // MARK: - Merging

    func testGraphMergeSumsSharedDaysAndModels() {
        let a = graph(day: "2026-11-12", tokens: 100, cost: 1)
        let b = GraphReport(contributions: [
            GraphReport.Day(date: "2026-11-12", tokenBreakdown: counts(50),
                            clients: [GraphReport.Day.Line(modelId: "claude-sonnet-5",
                                                           tokens: counts(50),
                                                           cost: 0.5, messages: 2),
                                            GraphReport.Day.Line(modelId: "gpt-5",
                                                                 tokens: counts(7),
                                                                 cost: 0.1, messages: 1)],
                            cost: 0.6, messages: 3),
            GraphReport.Day(date: "2026-11-13", tokenBreakdown: counts(9),
                            clients: [], cost: 0.2, messages: 1)
        ])
        let merged = GraphReport.merge([a, b])
        XCTAssertEqual(merged.contributions.map(\.date), ["2026-11-12", "2026-11-13"])

        let day = merged.contributions[0]
        XCTAssertEqual(day.tokenBreakdown, counts(150))
        XCTAssertEqual(day.cost, 1.6, accuracy: 0.0001)
        XCTAssertEqual(day.messages, 4)
        XCTAssertEqual(day.clients.count, 2)
        XCTAssertEqual(day.clients.first { $0.modelId == "claude-sonnet-5" }?.tokens,
                       counts(150))
    }

    func testLifetimeMergeSumsByModel() {
        let merged = UsageReport.merge([
            lifetime(model: "claude-sonnet-5", tokens: 100),
            UsageReport(entries: [UsageReport.Entry(model: "claude-sonnet-5",
                                                    tokens: counts(50), cost: 1, messages: 1),
                                  UsageReport.Entry(model: "gpt-5",
                                                    tokens: counts(7), cost: 1, messages: 1)],
                             messages: 2)
        ])
        XCTAssertEqual(merged.messages, 5)
        XCTAssertEqual(merged.entries.count, 2)
        XCTAssertEqual(merged.entries.first { $0.model == "claude-sonnet-5" }?.tokens,
                       counts(150))
    }

    /// The whole path a refresh takes: local reports plus a peer's, built
    /// into the digest the rings read.
    func testDigestSeesBothDevices() {
        let localGraph = graph(day: "2026-11-12", tokens: 100)
        let localLifetime = lifetime(model: "claude-sonnet-5", tokens: 100)
        let peer = report(deviceId: "mac-b", day: "2026-11-12", tokens: 50,
                          offsetMinutes: 0)
        // UTC on both sides, so the peer's day key needs no re-dating.
        let (peerGraph, peerLifetime) = peer.reports(calendar: calendar("UTC"))

        let digest = UsageDigest.build(
            graph: GraphReport.merge([localGraph, peerGraph]),
            lifetime: UsageReport.merge([localLifetime, peerLifetime]),
            now: ISO.parse("2026-11-12T12:00:00Z") ?? Date(),
            calendar: calendar("UTC"))
        XCTAssertEqual(digest.today.totals.tokens, 150)
        XCTAssertEqual(digest.lifetime.totals.tokens, 150)
    }

    // MARK: - Time zones

    private func calendar(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    func testSameOffsetKeepsTheSameDate() {
        // Both machines in Shanghai: nothing may move.
        XCTAssertEqual(DeviceSync.localDate(forPeerDay: "2026-11-12",
                                            peerOffsetMinutes: 480,
                                            calendar: calendar("Asia/Shanghai")),
                       "2026-11-12")
    }

    func testPeerDayGoesToTheReaderDayHoldingMostOfIt() {
        // A UTC peer's 11-12 is 08:00→08:00 in Shanghai: 16h on the 12th,
        // 8h on the 13th — the 12th keeps it.
        XCTAssertEqual(DeviceSync.localDate(forPeerDay: "2026-11-12",
                                            peerOffsetMinutes: 0,
                                            calendar: calendar("Asia/Shanghai")),
                       "2026-11-12")
        // Read from UTC, a +14 peer's 11-12 is 11-11 10:00→11-12 10:00:
        // 14h on the 11th, 10h on the 12th — the 11th keeps it.
        XCTAssertEqual(DeviceSync.localDate(forPeerDay: "2026-11-12",
                                            peerOffsetMinutes: 840,
                                            calendar: calendar("UTC")),
                       "2026-11-11")
    }

    func testAnExactBoundaryTieGoesToTheEarlierDay() {
        // UTC-12's day, read in UTC, splits exactly in half.
        XCTAssertEqual(DeviceSync.localDate(forPeerDay: "2026-11-12",
                                            peerOffsetMinutes: -720,
                                            calendar: calendar("UTC")),
                       "2026-11-12")
    }

    func testReportsRoundTripThroughTheReaderFrame() {
        var peer = report(deviceId: "mac-b", day: "2026-11-12", tokens: 10,
                          offsetMinutes: 840)
        peer.name = "MacBook"
        let (peerGraph, _) = peer.reports(calendar: calendar("UTC"))
        XCTAssertEqual(peerGraph.contributions.map(\.date), ["2026-11-11"])
        XCTAssertEqual(peerGraph.contributions[0].tokenBreakdown, counts(10))
    }
}

private enum ISO {
    static func parse(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
