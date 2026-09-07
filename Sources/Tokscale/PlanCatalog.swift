import Foundation

/// What each vendor's plans cost, at list price.
///
/// A catalogue rather than a number to type. Nobody knows their plan as a
/// figure — they know it as "Pro" or "Max", and looking the price up is work
/// the app can do once for everybody. It also means a detected plan id can be
/// turned into a price without asking anything at all.
///
/// These are published list prices in USD and can go out of date or differ by
/// region, team seat or promotion, which is why every vendor also offers a
/// custom amount.
enum PlanCatalog {
    struct Plan: Identifiable, Hashable {
        /// The vendor's own identifier where there is one to match against —
        /// `organizationType` for Anthropic — otherwise ours.
        let id: String
        let name: String
        let monthlyUSD: Double

        static let none = Plan(id: "none", name: "—", monthlyUSD: 0)
        static let custom = Plan(id: "custom", name: "…", monthlyUSD: 0)
    }

    static func plans(for vendor: Vendor) -> [Plan] {
        switch vendor {
        case .anthropic:
            return [
                Plan(id: "claude_pro", name: "Claude Pro", monthlyUSD: 20),
                Plan(id: "claude_max_5x", name: "Claude Max 5×", monthlyUSD: 100),
                Plan(id: "claude_max_20x", name: "Claude Max 20×", monthlyUSD: 200),
                Plan(id: "claude_team", name: "Claude Team", monthlyUSD: 30),
                Plan(id: "claude_enterprise", name: "Claude Enterprise", monthlyUSD: 0)
            ]
        case .openai:
            return [
                Plan(id: "chatgpt_plus", name: "ChatGPT Plus", monthlyUSD: 20),
                Plan(id: "chatgpt_pro", name: "ChatGPT Pro", monthlyUSD: 200),
                Plan(id: "chatgpt_business", name: "ChatGPT Business", monthlyUSD: 25),
                Plan(id: "chatgpt_enterprise", name: "ChatGPT Enterprise", monthlyUSD: 0)
            ]
        case .google:
            return [
                Plan(id: "google_ai_pro", name: "Google AI Pro", monthlyUSD: 19.99),
                Plan(id: "google_ai_ultra", name: "Google AI Ultra", monthlyUSD: 249.99)
            ]
        case .alibaba, .deepseek, .zhipu, .moonshot, .minimax, .xai,
             .xiaomi, .nvidia, .meta, .mistral, .other:
            // Metered by the token rather than subscribed to, at least in the
            // way these are reached here.
            return []
        }
    }

    static func plan(id: String, for vendor: Vendor) -> Plan? {
        plans(for: vendor).first { $0.id == id }
    }

    /// The menu's contents: nothing, the vendor's plans, and a way out.
    static func menu(for vendor: Vendor) -> [Plan] {
        [.none] + plans(for: vendor) + [.custom]
    }
}
