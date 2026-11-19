import Foundation

/// What one device publishes into the shared sync folder: the same two
/// reports tokscale produces locally, plus the timezone facts a reader in
/// another zone needs to line this device's day buckets up with its own.
///
/// Only aggregates cross the folder — tokens, cost and message counts per
/// model per day. No prompts, no file paths, nothing that identifies what
/// was worked on, which is the same promise the rest of the app makes about
/// the data it reads.
struct DeviceReport: Codable, Equatable {
    /// This install's stable id. Peers tell devices apart by it, and it is
    /// deliberately not the hostname, which changes.
    var deviceId: String
    /// What to call this device in the settings list, e.g. "wjia's MacBook".
    var name: String
    /// Minutes east of UTC *at export time*. Day buckets are local days;
    /// this is what lets a reader elsewhere place them.
    var utcOffsetMinutes: Int
    var timeZone: String
    var generatedAt: Date
    var days: [Day]
    var lifetime: [LifetimeEntry]
    /// The report's own message total, which is the figure tokscale stands
    /// behind — the per-entry counts are sessions, not requests.
    var lifetimeMessages: Int

    struct Day: Codable, Equatable {
        /// `yyyy-MM-dd` in the exporting device's own time zone.
        var date: String
        var tokens: TokenCounts
        var models: [ModelLine]
        var cost: Double
        var messages: Int
    }

    struct ModelLine: Codable, Equatable {
        var model: String
        /// Carried so a peer's Devin usage still recognises its vendor;
        /// optional so reports written before the field existed still read.
        var provider: String? = nil
        var tokens: TokenCounts
        var cost: Double
        var messages: Int
    }

    struct LifetimeEntry: Codable, Equatable {
        var model: String
        var provider: String? = nil
        var tokens: TokenCounts
        var cost: Double
        var messages: Int
    }

    init(graph: GraphReport, lifetime: UsageReport, deviceId: String, name: String,
         generatedAt: Date = Date()) {
        self.deviceId = deviceId
        self.name = name
        self.utcOffsetMinutes = TimeZone.current.secondsFromGMT() / 60
        self.timeZone = TimeZone.current.identifier
        self.generatedAt = generatedAt
        self.days = graph.contributions.map { day in
            Day(date: day.date, tokens: day.tokenBreakdown,
                models: day.clients.map {
                    ModelLine(model: $0.modelId, provider: $0.provider, tokens: $0.tokens,
                              cost: $0.cost, messages: $0.messages)
                },
                cost: day.cost, messages: day.messages)
        }
        self.lifetime = lifetime.entries.map {
            LifetimeEntry(model: $0.model, provider: $0.provider, tokens: $0.tokens,
                          cost: $0.cost, messages: $0.messages)
        }
        self.lifetimeMessages = lifetime.messages
    }

    /// This device's contribution as the two reports the digest reads, with
    /// its day keys re-dated into `calendar`'s zone when the exporting
    /// device keeps a different one. Lifetime needs no re-dating: a sum is
    /// the same sum in every time zone.
    func reports(calendar: Calendar = .current) -> (graph: GraphReport, lifetime: UsageReport) {
        let graph = GraphReport(contributions: days.map { day in
            GraphReport.Day(
                date: DeviceSync.localDate(forPeerDay: day.date,
                                           peerOffsetMinutes: utcOffsetMinutes,
                                           calendar: calendar),
                tokenBreakdown: day.tokens,
                clients: day.models.map {
                    GraphReport.Day.Line(modelId: $0.model, provider: $0.provider,
                                         tokens: $0.tokens,
                                         cost: $0.cost, messages: $0.messages)
                },
                cost: day.cost, messages: day.messages)
        })
        let lifetime = UsageReport(
            entries: lifetime.map {
                UsageReport.Entry(model: $0.model, provider: $0.provider, tokens: $0.tokens,
                                  cost: $0.cost, messages: $0.messages)
            },
            messages: lifetimeMessages)
        return (graph, lifetime)
    }
}

extension GraphReport {
    /// Every report added together: days that share a date sum their tokens,
    /// cost and messages, and model lines that share an id do too. This is
    /// what "this Mac plus the devices it can see" looks like to the digest.
    static func merge(_ reports: [GraphReport]) -> GraphReport {
        var byDate: [String: Day] = [:]
        for report in reports {
            for day in report.contributions {
                guard var existing = byDate[day.date] else {
                    byDate[day.date] = day
                    continue
                }
                var lines: [String: Day.Line] = [:]
                var order: [String] = []
                for line in existing.clients + day.clients {
                    if let prior = lines[line.modelId] {
                        lines[line.modelId] = Day.Line(
                            modelId: line.modelId,
                            provider: prior.provider ?? line.provider,
                            tokens: prior.tokens + line.tokens,
                            cost: prior.cost + line.cost,
                            messages: prior.messages + line.messages)
                    } else {
                        lines[line.modelId] = line
                        order.append(line.modelId)
                    }
                }
                existing = Day(date: day.date,
                               tokenBreakdown: existing.tokenBreakdown + day.tokenBreakdown,
                               clients: order.map { lines[$0]! },
                               cost: existing.cost + day.cost,
                               messages: existing.messages + day.messages)
                byDate[day.date] = existing
            }
        }
        return GraphReport(contributions: byDate.keys.sorted().compactMap { byDate[$0] })
    }
}

extension UsageReport {
    /// Every report added together, one row per model.
    static func merge(_ reports: [UsageReport]) -> UsageReport {
        var byModel: [String: Entry] = [:]
        var order: [String] = []
        var messages = 0
        for report in reports {
            messages += report.messages
            for entry in report.entries {
                if let prior = byModel[entry.model] {
                    byModel[entry.model] = Entry(
                        model: entry.model,
                        provider: prior.provider ?? entry.provider,
                        tokens: prior.tokens + entry.tokens,
                        cost: prior.cost + entry.cost,
                        messages: prior.messages + entry.messages)
                } else {
                    byModel[entry.model] = entry
                    order.append(entry.model)
                }
            }
        }
        return UsageReport(entries: order.map { byModel[$0]! }, messages: messages)
    }
}

/// Reading and writing the shared folder. Every file in it belongs to exactly
/// one device — a device only ever writes its own — so two Macs syncing the
/// same folder never produce a conflict.
enum DeviceSync {
    /// This device's file name in the folder.
    static func fileName(for deviceId: String) -> String { "\(deviceId).json" }

    /// Writes the report where peers will find it. The write is atomic — a
    /// sibling temp file renamed into place — so a sync client mid-transfer
    /// can never show a peer half a report.
    @discardableResult
    static func publish(_ report: DeviceReport, in directory: URL) -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(report) else { return false }
        try? FileManager.default.createDirectory(at: directory,
                                                  withIntermediateDirectories: true)
        let target = directory.appendingPathComponent(fileName(for: report.deviceId))
        return (try? data.write(to: target, options: .atomic)) != nil
    }

    /// Every other device's report in the folder. A file that will not
    /// decode — half-written by a sync client, or written by a newer
    /// version — is skipped rather than failing the whole read.
    static func peers(in directory: URL, excluding deviceId: String) -> [DeviceReport] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var reports: [DeviceReport] = []
        for file in files where file.pathExtension == "json" {
            guard file.deletingPathExtension().lastPathComponent != deviceId else { continue }
            guard let data = try? Data(contentsOf: file),
                  let report = try? decoder.decode(DeviceReport.self, from: data)
            else {
                // Half-written by a sync client, or written by a newer
                // version: skipped rather than failing the whole read.
                Log.usage.debug("skipping unreadable peer report \(file.lastPathComponent, privacy: .public)")
                continue
            }
            guard report.deviceId != deviceId else { continue }
            reports.append(report)
        }
        return reports.sorted { $0.generatedAt > $1.generatedAt }
    }

    /// Which of the reader's `yyyy-MM-dd` days a peer's day bucket mostly
    /// overlaps, once both are expressed as instants.
    ///
    /// Two local days are both 24 hours long but start at different offsets,
    /// so a peer's bucket can straddle a boundary here: it is given to
    /// whichever of the reader's days holds more of it. Same offset — the
    /// ordinary case of several devices in one place — always lands back on
    /// the same date.
    static func localDate(forPeerDay dayKey: String, peerOffsetMinutes: Int,
                          calendar: Calendar = .current) -> String {
        let parts = dayKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return dayKey }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        guard let dayStartUTC = utc.date(from: components) else { return dayKey }

        // The peer's local midnight as an absolute instant: its wall-clock
        // midnight read in UTC, shifted back by how far ahead of UTC it is.
        let start = dayStartUTC.addingTimeInterval(-Double(peerOffsetMinutes) * 60)
        let end = start.addingTimeInterval(86_400)

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        let first = formatter.string(from: start)
        // `end` is exclusive: the last instant inside the bucket is a second
        // before it, which is what decides whether a second reader-day is
        // touched at all.
        let last = formatter.string(from: end.addingTimeInterval(-1))
        guard first != last else { return first }

        // The bucket crosses into `last`. Its first instant is the reader's
        // midnight that opens that day; whichever side of it holds more of
        // the 24 hours wins the whole bucket.
        guard let boundary = formatter.date(from: last) else { return first }
        let before = boundary.timeIntervalSince(start)
        let after = end.timeIntervalSince(boundary)
        return before >= after ? first : last
    }
}
