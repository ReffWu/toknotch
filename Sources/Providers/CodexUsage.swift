import Foundation

/// Parses the rate-limit snapshot Codex records in its rollout log.
///
/// Codex writes a JSONL rollout per thread. Builds that surface usage emit a
/// `token_count` event carrying the account's own limit windows:
///
/// ```json
/// { "type": "event_msg",
///   "payload": { "type": "token_count",
///     "info": { "total_token_usage": { … }, "model_context_window": 258400 },
///     "rate_limits": {
///       "limit_id": "codex", "plan_type": "free",
///       "primary":   { "used_percent": 0.0, "window_minutes": 43200,
///                      "resets_at": 1790585719 },
///       "secondary": null,
///       "credits": { "has_credits": false, "unlimited": false } } } }
/// ```
///
/// Recorded from a live run. Note the reset is **`resets_at`, an absolute epoch
/// in seconds** — not the `resets_in_seconds` countdown the schema suggested.
/// Both are read, because a build that emits the other form should not silently
/// lose its reset time.
enum CodexUsage {
    /// Windows from the most recent rate-limit snapshot in a rollout.
    static func windows(fromRollout text: String, now: Date = Date()) throws -> [LimitWindow] {
        // The last snapshot wins: earlier lines are older readings of the same
        // windows, and a rollout is append-only.
        let snapshot = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .reversed()
            .lazy
            .filter { $0.contains("rate_limits") }
            .compactMap { line -> [String: Any]? in
                guard let data = line.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data)
                else { return nil }
                return rateLimits(in: object)
            }
            .first

        guard let snapshot else {
            throw UsageProviderError.nothingMetered("Codex has not recorded a usage snapshot yet")
        }

        let windows = [
            window(snapshot["primary"], id: "primary", now: now),
            window(snapshot["secondary"], id: "secondary", now: now)
        ].compactMap { $0 }

        guard !windows.isEmpty else {
            throw UsageProviderError.nothingMetered("Codex reported no usage windows")
        }
        return windows
    }

    /// When Codex actually took the reading.
    ///
    /// Needed because a rollout is a *file*: reading it always succeeds
    /// instantly, even when Codex last wrote to it days ago. Without this the
    /// provider reported a three-day-old percentage as a live one.
    static func recordedAt(inRollout text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]

        // Last line first: the newest snapshot is at the end.
        for line in text.split(separator: "\n").reversed() where line.contains("rate_limits") {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let dictionary = object as? [String: Any],
                  let stamp = dictionary["timestamp"] as? String
            else { continue }
            if let date = formatter.date(from: stamp) ?? plain.date(from: stamp) { return date }
        }
        return nil
    }

    /// `rate_limits` can sit at the top level or under `payload`, depending on
    /// how the event was framed.
    private static func rateLimits(in object: Any) -> [String: Any]? {
        guard let dictionary = object as? [String: Any] else { return nil }
        if let limits = dictionary["rate_limits"] as? [String: Any] { return limits }
        if let payload = dictionary["payload"] as? [String: Any] {
            return payload["rate_limits"] as? [String: Any]
        }
        return nil
    }

    private static func window(_ any: Any?, id: String, now: Date) -> LimitWindow? {
        guard let bucket = any as? [String: Any],
              let percent = (bucket["used_percent"] as? NSNumber)?.doubleValue
        else { return nil }

        let minutes = (bucket["window_minutes"] as? NSNumber)?.doubleValue

        // `resets_at` is an absolute epoch; `resets_in_seconds` is a countdown.
        // The live payload uses the former, the published schema the latter.
        let resetsAt: Date?
        if let absolute = (bucket["resets_at"] as? NSNumber)?.doubleValue {
            resetsAt = Date(timeIntervalSince1970: absolute)
        } else if let countdown = (bucket["resets_in_seconds"] as? NSNumber)?.doubleValue {
            resetsAt = now.addingTimeInterval(countdown)
        } else {
            resetsAt = nil
        }

        return LimitWindow(
            id: id,
            label: label(windowMinutes: minutes, fallback: id),
            usedFraction: percent / 100,
            resetsAt: resetsAt
        )
    }

    /// Codex names its windows only by length, so the label is derived from it —
    /// "5h limit" says more than "primary".
    static func label(windowMinutes: Double?, fallback: String) -> String {
        guard let minutes = windowMinutes, minutes > 0 else {
            return fallback == "primary" ? "Current session" : "Longer window"
        }
        if minutes < 60 { return "\(Int(minutes))m limit" }
        if minutes < 60 * 24 { return "\(Int(minutes / 60))h limit" }
        let days = Int((minutes / (60 * 24)).rounded())
        switch days {
        case 7:  return "Weekly limit"
        case 30: return "Monthly limit"
        default: return "\(days)d limit"
        }
    }
}
