import Foundation
import os

/// The OAuth token Antigravity holds for a Google account.
///
/// Borrowed, like every other credential here — Antigravity signs in, this only
/// reads what it stored.
struct AntigravityCredentials {
    let accessToken: String
    let expiresAt: Date
    /// `consumer` for a personal Google account; enterprise installs differ.
    let authMethod: String

    var isExpired: Bool { expiresAt <= Date() }

    static let service = "gemini"
    static let account = "antigravity"

    /// Held until it expires, for the reason spelled out in `CredentialCache`.
    private static let cache = CredentialCache<AntigravityCredentials> { $0.isExpired }

    static func forgetCached() { cache.forget() }

    /// Antigravity stores through Go's `keyring` package, which base64-encodes
    /// the payload behind this marker rather than writing raw JSON the way
    /// Claude Code does. Decoding it is not optional: without stripping the
    /// prefix the value is not JSON at all.
    private static let goKeyringPrefix = "go-keyring-base64:"

    static func load() throws -> AntigravityCredentials {
        try cache.value(
            itemModifiedAt: { KeychainItem.modifiedAt(service: service, account: account) },
            reload: read
        )
    }

    private static func read() throws -> AntigravityCredentials {
        var item: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ] as CFDictionary, &item)

        guard status == errSecSuccess, let data = item as? Data else {
            Log.usage.error("antigravity keychain read failed: OSStatus \(status)")
            throw ClaudeCredentials.wasRefused(status)
                ? UsageProviderError.accessDenied
                : UsageProviderError.needsAuth
        }

        guard let decoded = decode(data) else { throw UsageProviderError.needsAuth }
        return decoded
    }

    /// Split out so the decoding can be tested against a real stored value
    /// without a keychain.
    static func decode(_ data: Data) -> AntigravityCredentials? {
        guard var text = String(data: data, encoding: .utf8) else { return nil }
        if text.hasPrefix(goKeyringPrefix) {
            text = String(text.dropFirst(goKeyringPrefix.count))
        }
        guard let payload = Data(base64Encoded: text) else { return nil }

        struct Stored: Decodable {
            struct Token: Decodable {
                let access_token: String
                /// RFC 3339 with fractional seconds *and an offset* —
                /// "2026-08-31T21:53:49.575961+07:00". Not UTC, and not
                /// milliseconds since the epoch like Claude's. Parsing it as
                /// either is how a token that is live reads as long expired.
                let expiry: String
            }
            let auth_method: String
            let token: Token
        }

        guard let stored = try? JSONDecoder().decode(Stored.self, from: payload),
              let expiry = parse(stored.token.expiry)
        else { return nil }

        return AntigravityCredentials(accessToken: stored.token.access_token,
                                      expiresAt: expiry,
                                      authMethod: stored.auth_method)
    }

    /// Fractional seconds are not optional in this field, but a formatter that
    /// demands them fails on a whole-second timestamp — so try both.
    static func parse(_ value: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: value) { return date }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }
}
