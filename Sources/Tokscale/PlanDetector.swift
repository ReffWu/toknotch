import Foundation

/// A plan read from a tool's own configuration rather than typed in.
struct DetectedPlan: Equatable {
    let planID: String
    /// What the vendor calls it, when we recognise the id.
    let name: String
    /// List price for that plan, or nil when the id is one we do not know.
    let monthlyUSD: Double?
    /// The day of the month the subscription renews on, taken from when it
    /// started — Stripe bills on the anniversary of the first payment.
    let renewalDay: Int?
    /// Shown in settings, so it is never a mystery where a number came from.
    let source: String

    var subscription: Subscription? {
        guard let monthlyUSD, monthlyUSD > 0 else { return nil }
        return Subscription(monthlyUSD: monthlyUSD, renewalDay: renewalDay ?? 1,
                            planID: planID)
    }
}

/// Finds the plans a Mac is already signed in to.
///
/// Two kinds of source, and the difference matters:
///
/// * Claude Code keeps the account's plan in `~/.claude.json`, an ordinary
///   configuration file with no token in it.
/// * Codex keeps it inside the identity token in `~/.codex/auth.json`, which
///   *is* the credential store.
///
/// Neither goes near the keychain, so no password prompt can appear either way.
/// From the second, only the three plan claims are ever read — the plan type
/// and the dates around it. The access token, the refresh token and the API key
/// that sit beside them in the same file are never read, never copied and never
/// logged, and nothing from any of this leaves the machine.
enum PlanDetector {
    static func detect(fileManager: FileManager = .default) -> [Vendor: DetectedPlan] {
        var found: [Vendor: DetectedPlan] = [:]
        if let claude = detectClaude(fileManager: fileManager) { found[.anthropic] = claude }
        if let codex = detectCodex(fileManager: fileManager) { found[.openai] = codex }
        return found
    }

    // MARK: - Anthropic

    /// `~/.claude.json` → `oauthAccount.organizationType`, plus the date the
    /// subscription started.
    static func detectClaude(fileManager: FileManager = .default,
                             path: String? = nil) -> DetectedPlan? {
        let file = path ?? NSString(string: "~/.claude.json").expandingTildeInPath
        guard fileManager.isReadableFile(atPath: file),
              let data = fileManager.contents(atPath: file),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let account = root["oauthAccount"] as? [String: Any]
        else { return nil }

        // An account billed some other way — API credit, an enterprise
        // agreement — has no monthly figure to compare against.
        let billing = account["billingType"] as? String
        guard billing == nil || billing == "stripe_subscription" else { return nil }

        guard let type = account["organizationType"] as? String else { return nil }
        let known = PlanCatalog.plan(id: type, for: .anthropic)

        return DetectedPlan(
            planID: type,
            name: known?.name ?? readable(type),
            monthlyUSD: known?.monthlyUSD,
            renewalDay: (account["subscriptionCreatedAt"] as? String).flatMap { Self.day(ofISO: $0) },
            source: "~/.claude.json"
        )
    }

    // MARK: - OpenAI

    /// `~/.codex/auth.json` → the ChatGPT plan carried in the identity token.
    ///
    /// The plan is not in any of Codex's configuration files — its global state
    /// carries no plan, subscription or billing field at all — so the identity
    /// token is the only place on the machine that knows. Its payload is a
    /// plain base64url JSON claim set; it is decoded here, never verified and
    /// never sent anywhere, because the only thing being asked of it is a
    /// string the user already knows about themselves.
    static func detectCodex(fileManager: FileManager = .default,
                            path: String? = nil) -> DetectedPlan? {
        let file = path ?? NSString(string: "~/.codex/auth.json").expandingTildeInPath
        guard fileManager.isReadableFile(atPath: file),
              let data = fileManager.contents(atPath: file),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = root["tokens"] as? [String: Any],
              let identity = tokens["id_token"] as? String,
              let claims = self.claims(ofJWT: identity),
              let auth = claims["https://api.openai.com/auth"] as? [String: Any],
              let type = auth["chatgpt_plan_type"] as? String
        else { return nil }

        // A free account has nothing to weigh usage against.
        guard type.lowercased() != "free" else { return nil }

        let id = "chatgpt_\(type.lowercased())"
        let known = PlanCatalog.plan(id: id, for: .openai)
        return DetectedPlan(
            planID: id,
            name: known?.name ?? "ChatGPT \(type.capitalized)",
            monthlyUSD: known?.monthlyUSD,
            renewalDay: (auth["chatgpt_subscription_active_start"] as? String)
                .flatMap { Self.day(ofISO: $0) },
            source: "~/.codex/auth.json"
        )
    }

    /// A JWT's claim set, decoded but deliberately not verified.
    ///
    /// Verification would need OpenAI's signing keys and a network round trip,
    /// and would prove something nobody is asking about: this is not an
    /// authentication decision, it is reading a plan name the account holder
    /// already knows.
    static func claims(ofJWT token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    // MARK: - Shared

    /// The day of the month out of an ISO 8601 timestamp.
    static func day(ofISO string: String, calendar: Calendar = .current) -> Int? {
        // Both shapes occur: Claude writes fractional seconds, OpenAI does not.
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        let date = withFraction.date(from: string) ?? plain.date(from: string)
        return date.map { calendar.component(.day, from: $0) }
    }

    /// `claude_max_20x` → `Claude Max 20x`, for a plan id we do not have a
    /// price for. Better than showing the raw identifier.
    private static func readable(_ id: String) -> String {
        id.split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}
