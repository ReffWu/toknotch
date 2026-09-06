import Foundation
import SQLite3

/// The session Cursor's editor keeps for itself, in the SQLite global-state
/// store it inherits from VS Code.
///
/// Codenotch only ever reads it, the same bargain as Claude Code's keychain
/// token: the editor mints and refreshes it, we borrow the current value. The
/// database is opened read-only and `immutable`, so a running editor is never
/// blocked or corrupted by us looking.
struct CursorCredentials {
    let accountID: String
    let accessToken: String
    /// The web API wants the pair as one cookie.
    var sessionCookie: String { "WorkosCursorSessionToken=\(accountID)::\(accessToken)" }

    static var storeURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
    }

    /// Minted by ToDesktop, who build Cursor — stable across updates, but not
    /// across Cursor leaving ToDesktop or rebranding. Kept here beside the store
    /// path so the two facts about a Cursor installation change together: the
    /// activity monitor and the sign-in route both read this one.
    static let bundleID = "com.todesktop.230313mzl4w4u92"

    /// Identity, read from the same store as the session. Non-secret: the email
    /// and plan the editor caches for its own UI.
    static func account(from url: URL = storeURL) -> ProviderAccount? {
        guard let db = SQLiteStore.open(url) else { return nil }
        defer { sqlite3_close(db) }
        func value(_ key: String) -> String? {
            SQLiteStore.rows(in: db, sql: "SELECT value FROM ItemTable WHERE key = ?", bind: key).first
        }
        guard let email = value("cursorAuth/cachedEmail"), !email.isEmpty else { return nil }
        return ProviderAccount(
            label: email,
            plan: value("cursorAuth/stripeMembershipType"),
            source: "Cursor",
            manageURL: URL(string: "https://cursor.com/dashboard")
        )
    }

    static func load(from url: URL = storeURL) throws -> CursorCredentials {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw UsageProviderError.needsAuth
        }

        // Read-only, but *not* `immutable`. Cursor runs the database in WAL
        // mode, and `immutable=1` tells SQLite to ignore the write-ahead log —
        // so it happily returns whatever was true at the last checkpoint. That
        // is how you end up serving a token the editor has already rotated.
        guard let db = SQLiteStore.open(url) else { throw UsageProviderError.needsAuth }
        defer { sqlite3_close(db) }

        guard let token = value(forKey: "cursorAuth/accessToken", in: db),
              let account = value(forKey: "cursorAuth/stripeMembershipAuthId", in: db),
              !token.isEmpty, !account.isEmpty
        else { throw UsageProviderError.needsAuth }

        return CursorCredentials(accountID: account, accessToken: token)
    }

    private static func value(forKey key: String, in db: OpaquePointer?) -> String? {
        SQLiteStore.rows(in: db, sql: "SELECT value FROM ItemTable WHERE key = ?", bind: key).first
    }
}

