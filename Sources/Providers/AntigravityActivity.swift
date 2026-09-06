import Foundation

/// How much Antigravity has actually been used, counted from its own
/// transcripts.
///
/// This exists because Google publishes no usage figure. `loadCodeAssist`
/// returns tiers and nothing else, the conversation databases carry no token or
/// quota columns, and whatever metadata comes back on `streamGenerateContent`
/// is consumed by the stream and never written down. Counting locally is the
/// only honest number available.
///
/// It is a *count*, never a percentage. A fraction needs a limit and there is
/// no published limit to divide by — inventing a denominator would put a
/// confident ring on a guess.
struct AntigravityActivity: Equatable {
    let requestsToday: Int
    let lastRequest: Date?

    static var transcriptRoot: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".gemini/antigravity/brain")
    }

    /// A step the model actually answered. User input and system checkpoints
    /// share the transcript, and counting those would inflate the number with
    /// work the model never did.
    private static let modelSource = "MODEL"

    static func read(root: URL = transcriptRoot, now: Date = Date()) -> AntigravityActivity {
        let manager = FileManager.default
        guard let trajectories = try? manager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil
        ) else { return AntigravityActivity(requestsToday: 0, lastRequest: nil) }

        var today = 0
        var latest: Date?
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current

        for trajectory in trajectories {
            let transcript = trajectory
                .appendingPathComponent(".system_generated/logs/transcript.jsonl")
            guard let text = try? String(contentsOf: transcript, encoding: .utf8) else { continue }

            for line in text.split(separator: "\n") {
                guard let data = line.data(using: .utf8),
                      let step = try? JSONDecoder().decode(Step.self, from: data),
                      step.source == modelSource,
                      let at = parse(step.created_at)
                else { continue }

                if latest == nil || at > latest! { latest = at }
                // `created_at` is UTC — the trailing Z is not decoration. The
                // comparison has to be against the *local* day, which is what
                // `isDate(_:inSameDayAs:)` on a local calendar does; treating
                // the timestamp as local instead would move every count either
                // side of midnight by the offset.
                if calendar.isDate(at, inSameDayAs: now) { today += 1 }
            }
        }
        return AntigravityActivity(requestsToday: today, lastRequest: latest)
    }

    private struct Step: Decodable {
        let created_at: String
        let source: String?
    }

    static func parse(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }

    /// What the cell says. Deliberately a count with the limit's absence stated,
    /// rather than a number that looks like a percentage.
    var summary: String {
        guard requestsToday > 0 else { return "no requests today" }
        return "~\(requestsToday) request\(requestsToday == 1 ? "" : "s") today"
    }
}
