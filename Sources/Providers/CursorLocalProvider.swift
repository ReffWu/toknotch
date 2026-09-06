import Foundation
import os

/// Reads Cursor usage as the account the *editor* is signed into.
///
/// This replaced a WebView sign-in, and the reason is worth keeping: signing
/// into cursor.com inside the app created a second, empty account, so the notch
/// faithfully reported zero usage for someone who was not the user. Borrowing
/// the editor's own session removes the question — there is only ever one
/// account, the one actually being used.
actor CursorLocalProvider: UsageProvider {
    nonisolated let id = "cursor"
    nonisolated let displayName = "Cursor"
    nonisolated let glyph = ProviderGlyph.cursor

    private let endpoint = URL(string: "https://cursor.com/api/usage-summary")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    nonisolated var signInRoute: SignInRoute { .openApp(bundleID: CursorCredentials.bundleID, name: "Cursor") }

    nonisolated func account() -> ProviderAccount? { CursorCredentials.account() }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        // Re-read every time: the editor rotates this, and holding a stale copy
        // would mean signing ourselves out for no reason.
        let credentials = try CursorCredentials.load()

        var request = URLRequest(url: endpoint)
        request.setValue(credentials.sessionCookie, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        if status == 401 || status == 403 { throw UsageProviderError.needsAuth }
        guard (200..<300).contains(status) else {
            throw UsageProviderError.badResponse(status: status)
        }

        let body = String(data: data, encoding: .utf8) ?? ""
        Log.usage.debug("cursor usage -> \(body.prefix(900), privacy: .public)")

        return ProviderSnapshot(
            id: id,
            displayName: displayName,
            glyph: glyph,
            fidelity: .official,
            status: .ok,
            windows: try CursorUsage.windows(fromJSON: body),
            headlineID: "included"
        )
    }
}
