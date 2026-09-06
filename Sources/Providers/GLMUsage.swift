import Foundation

/// Parses the answer from Z.ai's own usage monitor,
/// `GET /api/monitor/usage/quota/limit`.
///
/// The Coding Plan does not meter tokens the way Anthropic meters prompts — it
/// reports three separate allowances in one response, and the window each
/// token limit belongs to is encoded rather than named:
///
/// ```json
/// { "code": 200, "success": true,
///   "data": { "level": "pro",
///     "limits": [
///       { "type": "TOKENS_LIMIT", "unit": 3, "number": 5,
///         "percentage": 12.5, "currentValue": 1250000, "usage": 12000000,
///         "nextResetTime": 1788682200000 },
///       { "type": "TOKENS_LIMIT", "unit": 6, "number": 1,
///         "percentage": 8.1, "nextResetTime": 1789190400000 },
///       { "type": "TIME_LIMIT", "percentage": 4.0,
///         "currentValue": 40, "usage": 1000 } ] } }
/// ```
///
/// `unit`/`number` pair up as (hours, 5) for the rolling session and
/// (weeks, 1) for the weekly allowance; `TIME_LIMIT` is the monthly MCP call
/// budget. What is being metered inside a window varies by plan — token plans
/// answer `TOKENS_LIMIT`, credit plans `CREDIT_LIMIT` — and both pair the
/// window length with the same `unit`/`number`, so it is the length the
/// identity is built from, not the meter. The shape is pinned by tests,
/// including a response recorded from a live credit plan: the endpoint is not
/// a published API, and this is the first place a change would show.
///
/// Two things about this endpoint differ from the others here, and both are
/// load-bearing. Errors ride in under an HTTP 200 — `{ "code": 401, "success":
/// false }` is what an expired token looks like on the wire — so the envelope
/// is read before the payload is trusted. And the MCP row never carries a
/// reset time, so unlike Claude's windows a row is not dropped for lacking
/// one; a percentage with no countdown is still a reading.
enum GLMUsage {
    struct Payload {
        /// The plan's own name for itself, lowercase — "pro", "max". Nil when
        /// the response declines to say.
        let level: String?
        let windows: [LimitWindow]
    }

    /// The envelope plus payload shape.
    struct Response: Decodable {
        struct Limit: Decodable {
            let type: String?
            let unit: Int?
            let number: Int?
            let percentage: Double?
            let currentValue: Double?
            let usage: Double?
            let total: Double?
            /// Milliseconds since the epoch, not seconds — the one unit this
            /// API shares with JavaScript rather than with Unix.
            let nextResetTime: Double?
        }
        struct Data: Decodable {
            let level: String?
            let limits: [Limit]?
        }

        let code: Int?
        let success: Bool?
        let msg: String?
        let data: Data?
    }

    /// True only when the envelope says the request itself succeeded.
    static func succeeded(_ response: Response) -> Bool {
        (response.success ?? false) || response.code == nil || response.code == 200
    }

    /// The failure the envelope describes, if it describes one.
    static func failure(in response: Response) -> UsageProviderError? {
        guard !succeeded(response) else { return nil }
        switch response.code {
        case 401, 403: return .needsAuth
        case 429:      return .rateLimited(retryAfter: 0)
        case .some(let code): return .badResponse(status: code)
        case nil:      return .badResponse(status: 200)
        }
    }

    static func parse(_ data: Data) throws -> Payload {
        let response = try JSONDecoder().decode(Response.self, from: data)
        if let failure = failure(in: response) { throw failure }
        return Payload(level: response.data?.level,
                       windows: windows(in: response.data?.limits ?? []))
    }

    /// Turns the limits array into limit windows, session first.
    static func windows(in limits: [Response.Limit]) -> [LimitWindow] {
        limits.compactMap { window(for: $0) }.sorted(by: Self.displayOrder)
    }

    private static func window(for limit: Response.Limit) -> LimitWindow? {
        // Without a percentage there is nothing to draw: a bare count from an
        // unnamed allowance would be a reading we invented a scale for.
        guard let percentage = limit.percentage else { return nil }

        return LimitWindow(
            id: Self.id(for: limit),
            label: Self.label(for: limit),
            usedFraction: percentage / 100,
            resetsAt: limit.nextResetTime.map { Date(timeIntervalSince1970: $0 / 1000) }
        )
    }

    /// Which window this is, encoded in `unit`/`number`.
    ///
    /// (hours, 5) is the rolling session — the Coding Plan's "next 5-hour
    /// cycle" — and (weeks, 1) the weekly allowance. The *type* token is
    /// deliberately not part of the identity: token plans answer
    /// `TOKENS_LIMIT`, credit plans answer `CREDIT_LIMIT`, and both encode the
    /// window length the same way. `TIME_LIMIT` is the monthly MCP budget and
    /// carries no unit/number at all.
    static func id(for limit: Response.Limit) -> String {
        switch limit.type {
        case "TIME_LIMIT":
            return "mcp"
        default:
            switch (limit.unit, limit.number) {
            case (3?, 5?):    return "session"
            case (6?, 1?):    return "weekly"
            case (.some(let unit), .some(let number)):
                return "window-\(unit)x\(number)"
            default:
                return limit.type?.lowercased() ?? "unknown"
            }
        }
    }

    /// The frame's wording, for the windows it knows.
    static func label(for limit: Response.Limit) -> String {
        switch id(for: limit) {
        case "session": return "Current session"
        case "weekly":  return "Weekly"
        case "mcp":     return "MCP (1 month)"
        case let id     where id.hasPrefix("window-"):
            switch (limit.unit, limit.number) {
            case (3?, .some(let number)): return "Usage (\(number) h)"
            case (6?, .some(let number)): return "Usage (\(number) wk)"
            default:                      return "Usage"
            }
        default:        return "Usage"
        }
    }

    /// Session first, then weekly, then MCP — the order the plan's own panel
    /// leads with.
    private static func displayOrder(_ a: LimitWindow, _ b: LimitWindow) -> Bool {
        func rank(_ id: String) -> Int {
            switch id {
            case "session": return 0
            case "weekly":  return 1
            case "mcp":     return 2
            default:        return 3
            }
        }
        let (ra, rb) = (rank(a.id), rank(b.id))
        return ra == rb ? a.id < b.id : ra < rb
    }
}
