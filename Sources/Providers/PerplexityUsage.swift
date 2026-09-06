import Foundation

/// Parses `GET /rest/rate-limit/all` on perplexity.ai.
///
/// Written against a recorded response, not a guess:
///
/// ```json
/// { "free_queries": { "available": true,
///                     "remaining_detail": { "kind": "exact", "remaining": 10 } },
///   "model_specific_limits": {},
///   "remaining_agentic_research": 0,
///   "remaining_labs": 0,
///   "remaining_pro": 2,
///   "remaining_research": 0,
///   "sources": { "source_to_limit": { … connector quotas … } } }
/// ```
///
/// The shape settles how Perplexity can be displayed at all: it reports **only
/// what is left**. No totals, so there is no denominator for a percentage, and
/// no reset times either. So the notch shows the count — "2 left" — rather than
/// a percentage worked back from a limit nobody stated. `sources` is a long tail
/// of connector quotas unrelated to model usage, and is ignored.
enum PerplexityUsage {
    /// The quotas worth a line, in the order they are shown. The first is the
    /// headline, so it is the one people actually run out of.
    private static let counters: [(key: String, label: String)] = [
        ("remaining_pro", "Pro searches"),
        ("remaining_research", "Research"),
        ("remaining_agentic_research", "Agentic research"),
        ("remaining_labs", "Labs")
    ]

    static func windows(fromJSON json: String) throws -> [LimitWindow] {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw UsageProviderError.badResponse(status: 0) }

        var windows: [LimitWindow] = []

        for counter in counters {
            guard let remaining = (root[counter.key] as? NSNumber)?.intValue else { continue }
            windows.append(
                LimitWindow(id: counter.key, label: counter.label, remaining: remaining)
            )
        }

        // Free queries are nested, and only meaningful when Perplexity says the
        // count is exact — it also reports vaguer kinds we cannot put a number on.
        if let free = root["free_queries"] as? [String: Any],
           let detail = free["remaining_detail"] as? [String: Any],
           (detail["kind"] as? String) == "exact",
           let remaining = (detail["remaining"] as? NSNumber)?.intValue {
            windows.append(
                LimitWindow(id: "free_queries", label: "Free queries", remaining: remaining)
            )
        }

        guard !windows.isEmpty else { throw UsageProviderError.badResponse(status: 0) }
        return windows
    }
}
