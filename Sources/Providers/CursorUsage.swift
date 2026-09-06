import Foundation

/// Parses Cursor's `GET /api/usage-summary`, recorded from a live free account:
///
/// ```json
/// { "billingCycleStart": "2026-08-24T03:32:15.933Z",
///   "billingCycleEnd":   "2026-09-24T03:32:15.933Z",
///   "membershipType": "free", "isUnlimited": false,
///   "individualUsage": {
///     "plan": { "enabled": true, "used": 0, "limit": 0, "remaining": 0,
///               "breakdown": { "included": 0, "bonus": 19, "total": 19 },
///               "autoPercentUsed": 0, "apiPercentUsed": 19,
///               "totalPercentUsed": 9.5 },
///     "onDemand": { "enabled": false, "used": 0, "limit": null } } }
/// ```
///
/// Cursor meters an **allowance, not a request count** — the dashboard's "Your
/// included usage · N% used" is `totalPercentUsed`. The `used`/`limit` pair sits
/// at zero on a free plan even while real usage is happening, because the
/// allowance arrives as `breakdown.bonus` rather than as a dollar limit. Reading
/// `used`/`limit` therefore reports 0% for an account that is 10% through its
/// month, which is exactly what this parser used to do.
enum CursorUsage {
    static func windows(fromJSON json: String) throws -> [LimitWindow] {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw UsageProviderError.badResponse(status: 0) }

        let resetsAt = date(root["billingCycleEnd"])
        let usage = root["individualUsage"] as? [String: Any] ?? [:]
        let plan = usage["plan"] as? [String: Any] ?? [:]

        var windows: [LimitWindow] = []

        // The headline, and the one the dashboard shows.
        //
        // Zero is a reading, not an absence. A free plan reports
        // `totalPercentUsed: 0` beside `limit: 0`, and it is tempting to read
        // that as "no allowance to be a percentage of" — but Cursor itself
        // ships the answer in the same response:
        // "You've used 0% of your included total usage". If Cursor calls it 0%,
        // so does this. Suppressing it hid a correct reading from an account
        // that had genuinely just been switched.
        if let total = percent(plan["totalPercentUsed"]) {
            windows.append(LimitWindow(id: "included", label: "Included usage",
                                       usedFraction: total, resetsAt: resetsAt))
        }
        // Reported separately by Cursor, and can be far ahead of the total.
        if let api = percent(plan["apiPercentUsed"]), api > 0 {
            windows.append(LimitWindow(id: "api", label: "API usage",
                                       usedFraction: api, resetsAt: resetsAt))
        }
        if let onDemand = spendWindow(usage["onDemand"], id: "on_demand",
                                      label: "On demand", resetsAt: resetsAt) {
            windows.append(onDemand)
        }

        guard windows.isEmpty else { return windows }

        let membership = (root["membershipType"] as? String) ?? "this"
        if (root["isUnlimited"] as? Bool) == true {
            throw UsageProviderError.nothingMetered("Unlimited on the \(membership) plan — nothing to meter")
        }
        throw UsageProviderError.nothingMetered("The \(membership) plan has nothing for Cursor to meter yet")
    }

    /// A dollar-denominated bucket, used where a plan states a real ceiling.
    private static func spendWindow(
        _ any: Any?, id: String, label: String, resetsAt: Date?
    ) -> LimitWindow? {
        guard let bucket = any as? [String: Any],
              (bucket["enabled"] as? Bool) == true,
              let limit = (bucket["limit"] as? NSNumber)?.doubleValue, limit > 0,
              let used = (bucket["used"] as? NSNumber)?.doubleValue
        else { return nil }
        return LimitWindow(id: id, label: label, usedFraction: used / limit, resetsAt: resetsAt)
    }

    /// Cursor reports 0–100; the rest of the app works in 0–1.
    private static func percent(_ any: Any?) -> Double? {
        guard let number = any as? NSNumber else { return nil }
        return number.doubleValue / 100
    }

    private static func date(_ any: Any?) -> Date? {
        guard let text = any as? String else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
    }
}
