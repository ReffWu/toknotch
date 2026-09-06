import Foundation

/// The Z.ai key behind a GLM Coding Plan, borrowed from whichever tool holds
/// it.
///
/// Z.ai does not ship a desktop app for the plan, so there is no single
/// session to borrow the way Claude Code's or Cursor's is borrowed. What it
/// has is an API key that several coding tools will hold on the user's behalf,
/// and a notch that wants to read one of them rather than ask for a key of its
/// own. The sources, in the order they are tried:
///
/// 1. **Claude Code** — `~/.claude/settings.json`, the documented way to point
///    Claude Code at the plan. Only claimed when the base URL alongside the
///    token is a Z.ai one: `ANTHROPIC_AUTH_TOKEN` aimed at api.anthropic.com
///    is somebody's Anthropic key, and claiming it would read the wrong
///    account and report it under GLM's name.
/// 2. **ZCode** — two files. `~/.zcode/v2/config.json` is where a plan key is
///    pasted in directly: an enabled `builtin:*-coding-plan` entry with a
///    plaintext `apiKey`, and the `baseURL` beside it says which console the
///    key belongs to. `~/.zcode/v2/credentials.json` holds the token from
///    signing into the plan through the app instead; recent builds encrypt it
///    at rest behind an `enc:v1:` marker, and those are skipped rather than
///    guessed at — decrypting them is ZCode's business, and a wrong guess
///    would read as a signed-out plan.
/// 3. **OpenCode** — `~/.local/share/opencode/auth.json`, keyed under a
///    handful of provider names for the global (`z.ai`) and China
///    (`bigmodel.cn`) consoles.
enum GLMCredentials {
    struct Credential {
        let token: String
        /// The console this key belongs to — it decides the monitor host the
        /// usage is read from. A China-console key asked of api.z.ai answers
        /// as an auth failure, which would read as a signed-out plan that is
        /// merely pointed at the other country.
        let baseURL: URL
        /// The tool the key was found under, for the settings row.
        let source: String
    }

    static var claudeSettingsURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/settings.json")
    }
    static var zcodeConfigURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".zcode/v2/config.json")
    }
    static var zcodeCredentialsURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".zcode/v2/credentials.json")
    }
    static var openCodeAuthURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".local/share/opencode/auth.json")
    }

    static func load() -> Credential? {
        load(claudeSettings: claudeSettingsURL,
             zcodeConfig: zcodeConfigURL,
             zcodeCredentials: zcodeCredentialsURL,
             openCodeAuth: openCodeAuthURL)
    }

    /// Every path is a parameter so a test can point each source at its own
    /// fixture without touching a real one. A nil path simply drops that
    /// source.
    static func load(claudeSettings: URL?, zcodeConfig: URL?,
                     zcodeCredentials: URL?, openCodeAuth: URL?) -> Credential? {
        claudeSettings.flatMap(claudeCode)
            ?? zcodeConfig.flatMap(zcodePlanKey)
            ?? zcodeCredentials.flatMap(zcode)
            ?? openCodeAuth.flatMap(openCode)
    }

    // MARK: Claude Code

    /// `~/.claude/settings.json` → `env.ANTHROPIC_AUTH_TOKEN` plus
    /// `env.ANTHROPIC_BASE_URL`.
    static func claudeCode(_ url: URL) -> Credential? {
        guard let root = dictionary(at: url), let env = root["env"] as? [String: Any],
              let token = string(env["ANTHROPIC_AUTH_TOKEN"]) ?? string(env["ANTHROPIC_API_KEY"])
        else { return nil }

        // The base URL is what makes this a GLM key. Without it, or pointed
        // somewhere else, the token is not ours to claim.
        guard let base = string(env["ANTHROPIC_BASE_URL"]),
              let url = URL(string: base),
              let host = url.host,
              isZaiHost(host)
        else { return nil }

        return Credential(token: token, baseURL: consoleBase(from: host), source: "Claude Code")
    }

    // MARK: ZCode

    static let encryptedMarker = "enc:v1:"

    /// `~/.zcode/v2/config.json` → an enabled `builtin:*-coding-plan` provider
    /// with the plan key pasted in. The `baseURL` beside it is the tool's own
    /// Anthropic endpoint — its *host* decides which console the usage is read
    /// from, the path is dropped: the monitor lives at the console root, and
    /// asking it under `/api/anthropic` answers a misleading 404.
    static func zcodePlanKey(_ url: URL) -> Credential? {
        guard let root = dictionary(at: url), let providers = root["provider"] as? [String: Any]
        else { return nil }

        for (id, value) in providers.sorted(by: { $0.key < $1.key }) {
            guard id.contains("coding-plan"), let provider = value as? [String: Any],
                  let options = provider["options"] as? [String: Any],
                  let key = string(options["apiKey"])
            else { continue }
            // Explicitly disabled entries are not keys being used; claiming
            // one would read an account the user switched off.
            if let enabled = provider["enabled"] as? Bool, !enabled { continue }
            let console = (string(options["baseURL"]))
                .flatMap { URL(string: $0) }
                .flatMap { $0.host }
                .map(consoleBase(from:)) ?? URL(string: "https://api.z.ai")!
            return Credential(token: key, baseURL: console, source: "ZCode")
        }
        return nil
    }

    static func zcode(_ url: URL) -> Credential? {
        guard let root = dictionary(at: url),
              let token = string(root["oauth:zai:access_token"])
        else { return nil }

        // Encrypted at rest: a string we cannot read is a string we must not
        // send. Skipping the source means "not found", which the row reports
        // honestly, rather than a 401 from the monitor that means nothing.
        guard !token.hasPrefix(encryptedMarker) else { return nil }

        return Credential(token: token, baseURL: URL(string: "https://api.z.ai")!, source: "ZCode")
    }

    // MARK: OpenCode

    /// The provider names OpenCode's own sign-in writes, most specific first.
    private static let openCodeProviderIDs = ["zai-coding-plan", "zai", "z-ai", "z.ai", "zhipu", "zhipuai"]

    static func openCode(_ url: URL) -> Credential? {
        guard let root = dictionary(at: url) else { return nil }
        for id in openCodeProviderIDs {
            guard let entry = root[id] else { continue }
            // The entry is either the key itself or an object carrying it —
            // both shapes have shipped.
            if let token = string(entry) {
                return Credential(token: token, baseURL: console(forProviderID: id), source: "OpenCode")
            }
            if let object = entry as? [String: Any] {
                let key = ["apiKey", "api_key", "token", "key", "accessToken", "auth_token"]
                    .compactMap { string(object[$0]) }.first
                if let key {
                    return Credential(token: key, baseURL: console(forProviderID: id), source: "OpenCode")
                }
            }
        }
        return nil
    }

    /// The provider id decides the console: the `zhipu` names sign into the
    /// China console, everything else the global one.
    static func console(forProviderID id: String) -> URL {
        id.hasPrefix("zhipu")
            ? URL(string: "https://open.bigmodel.cn")!
            : URL(string: "https://api.z.ai")!
    }

    // MARK: Shared

    static func isZaiHost(_ host: String) -> Bool {
        host == "api.z.ai" || host.hasSuffix(".z.ai")
            || host == "open.bigmodel.cn" || host.hasSuffix(".bigmodel.cn")
    }

    static func consoleBase(from host: String) -> URL {
        host.hasSuffix("bigmodel.cn")
            ? URL(string: "https://open.bigmodel.cn")!
            : URL(string: "https://api.z.ai")!
    }

    private static func dictionary(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return root
    }

    /// Non-empty strings only: an empty key is worse than a missing one, it is
    /// a request that cannot succeed being sent all the same.
    private static func string(_ value: Any?) -> String? {
        (value as? String).flatMap { $0.isEmpty ? nil : $0 }
    }
}
