import AppKit
import WebKit
import os

/// Reads a provider's usage from the endpoint its own web app uses, by running
/// the request *inside a browser the user signs into themselves*.
///
/// **Why a WebView rather than a cookie.** Some of these sites sit behind bot
/// management — an unauthenticated probe of Perplexity's endpoint comes back
/// `403 cf-mitigated: challenge`. A session cookie does not help, because the
/// `cf_clearance` beside it is bound to the TLS and HTTP fingerprint of the
/// browser that earned it. Making `URLSession` pass would mean impersonating
/// Chrome, which is defeating bot detection rather than reading your own usage.
/// Lifting cookies out of Chrome's encrypted store is its own problem again.
///
/// So the request is made by a browser: a WKWebView with the app's own
/// persistent store. Nothing is taken from Chrome or Safari, no fingerprint is
/// faked, and a challenge is only ever answered by the person sitting there.
@MainActor
final class WebSessionProvider: NSObject, UsageProvider {
    /// Everything site-specific, so the browser plumbing is written once.
    struct Site {
        let id: String
        let displayName: String
        let glyph: ProviderGlyph
        let origin: URL
        /// Runs in the page as an async function body. Must return a JSON string
        /// `{ "status": Int, "body": String }`.
        let script: String
        /// Turns the response body into windows, or throws if it cannot.
        let parse: (String) throws -> [LimitWindow]
    }

    nonisolated let id: String
    nonisolated let displayName: String
    nonisolated let glyph: ProviderGlyph
    /// A browser-session provider is the one kind that really can sign you in:
    /// the session lives in its own WebView, so it can open one and clear one.
    nonisolated var signInRoute: SignInRoute { .modal(name: displayName) }

    private let site: Site
    private var webView: WKWebView?
    private var signInWindow: NSWindow?
    private var isLoaded = false

    init(site: Site) {
        self.site = site
        self.id = site.id
        self.displayName = site.displayName
        self.glyph = site.glyph
        super.init()
    }

    /// Set once a sign-in has been opened. Until then the provider makes no
    /// request at all: quietly loading someone's account page in a hidden
    /// WebView every minute, unasked, would be both wasteful and reasonably
    /// indistinguishable from automation.
    private var hasSignedIn: Bool {
        get { UserDefaults.standard.bool(forKey: "\(site.id).signedIn") }
        set { UserDefaults.standard.set(newValue, forKey: "\(site.id).signedIn") }
    }

    // MARK: - The browser

    private func makeWebViewIfNeeded() -> WKWebView {
        if let webView { return webView }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()   // persists across launches
        // Records the API calls the page makes, so an endpoint can be found by
        // watching the site rather than by guessing at path names. Injected at
        // document start, because the interesting calls happen during load.
        configuration.userContentController.addUserScript(WKUserScript(
            source: #"""
            window.__notchCalls = [];
            (function () {
                const fetchImpl = window.fetch;
                window.fetch = function (...args) {
                    try {
                        const url = args[0] && args[0].url ? args[0].url : args[0];
                        window.__notchCalls.push(String(url));
                    } catch (e) {}
                    return fetchImpl.apply(this, args);
                };
                const openImpl = XMLHttpRequest.prototype.open;
                XMLHttpRequest.prototype.open = function (method, url) {
                    try { window.__notchCalls.push(String(url)); } catch (e) {}
                    return openImpl.apply(this, arguments);
                };
            })();
            """#,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1100, height: 800),
                                configuration: configuration)
        self.webView = webView
        return webView
    }

    private func ensureLoaded() async throws {
        let webView = makeWebViewIfNeeded()
        if isLoaded, webView.url != nil { return }
        webView.load(URLRequest(url: site.origin))
        for _ in 0..<40 {
            try await Task.sleep(nanoseconds: 250_000_000)
            if let host = webView.url?.host, host.contains(site.origin.host ?? ""), !webView.isLoading {
                isLoaded = true
                return
            }
        }
        Log.usage.error("\(self.site.id, privacy: .public) page never reached a same-origin state")
        throw UsageProviderError.badResponse(status: 0)
    }

    // MARK: - Fetching

    func fetchSnapshot() async throws -> ProviderSnapshot {
        guard hasSignedIn else { throw UsageProviderError.needsAuth }
        try await ensureLoaded()
        guard let webView else { throw UsageProviderError.needsAuth }

        // `callAsyncJavaScript`, not `evaluateJavaScript`. The latter returns
        // whatever the last expression evaluates to and never awaits it, so an
        // async body hands back an unresolved Promise — an unsupported type,
        // which surfaces as an opaque failure instead of the response.
        let result: Any?
        do {
            result = try await webView.callAsyncJavaScript(
                site.script, arguments: [:], in: nil, contentWorld: .page
            )
        } catch {
            Log.usage.error("\(self.site.id, privacy: .public) fetch script failed: \(error.localizedDescription, privacy: .public)")
            throw UsageProviderError.badResponse(status: 0)
        }

        guard let text = result as? String,
              let data = text.data(using: .utf8),
              let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = envelope["status"] as? Int,
              let body = envelope["body"] as? String
        else {
            Log.usage.error("\(self.site.id, privacy: .public) response unreadable: \(String(describing: result), privacy: .public)")
            throw UsageProviderError.badResponse(status: 0)
        }

        if status == 401 || status == 403 {
            // Not signed in, or a challenge wants a human. Same remedy either way.
            throw UsageProviderError.needsAuth
        }
        guard (200..<300).contains(status) else {
            throw UsageProviderError.badResponse(status: status)
        }

        // Recorded verbatim so a parser can be written against the real thing.
        Log.usage.notice("\(self.site.id, privacy: .public) usage -> \(body.prefix(1200), privacy: .public)")
        if let probes = envelope["probes"] as? String {
            Log.usage.notice("\(self.site.id, privacy: .public) probes -> \(probes.prefix(2600), privacy: .public)")
        }

        return ProviderSnapshot(
            id: id,
            displayName: displayName,
            glyph: glyph,
            fidelity: .official,
            status: .ok,
            windows: try site.parse(body)
        )
    }

    /// Loads a page and reports the API calls it made. A discovery tool, not
    /// part of a refresh.
    func recordCalls(on url: URL, settleFor seconds: Double = 8) async -> [String] {
        let webView = makeWebViewIfNeeded()
        webView.load(URLRequest(url: url))
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        isLoaded = false   // the page moved; the next refresh reloads its own
        let result = try? await webView.callAsyncJavaScript(
            "return JSON.stringify(window.__notchCalls || []);",
            arguments: [:], in: nil, contentWorld: .page
        )
        guard let text = result as? String,
              let data = text.data(using: .utf8),
              let calls = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        // No "/api/" filter: a tRPC or GraphQL endpoint would not match it, and
        // missing the one call that matters is the whole failure mode here.
        let interesting = calls.filter { url in
            !url.hasSuffix(".js") && !url.hasSuffix(".css") && !url.hasSuffix(".woff2")
                && !url.contains("/_next/static/") && !url.contains("data:")
        }
        return Array(Set(interesting)).sorted()
    }

    // MARK: - Signing in

    /// Shows the WebView so the user can sign in — and, if a challenge appears,
    /// answer it themselves. The app never answers one on their behalf.
    /// The one real logout in the app: this session belongs to Codenotch, so
    /// Codenotch can end it.
    ///
    /// Scoped to the site's own host rather than emptying the store — the
    /// default store is shared, so clearing all of it would sign the user out of
    /// every other web provider at the same time.
    func signOut() async {
        hasSignedIn = false
        isLoaded = false

        guard let host = site.origin.host else { return }
        let store = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await store.dataRecords(ofTypes: types).filter {
            $0.displayName == host || host.hasSuffix(".\($0.displayName)")
        }
        await store.removeData(ofTypes: types, for: records)

        // Drop the WebView too: it holds the loaded page in memory, and a
        // cleared cookie jar behind a still-authenticated page would keep
        // answering until something happened to reload it.
        webView = nil
    }

    func presentSignIn() {
        let webView = makeWebViewIfNeeded()
        if let signInWindow {
            signInWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 800),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Sign in to \(displayName)"
        window.contentView = webView
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        signInWindow = window
        webView.load(URLRequest(url: site.origin))
        isLoaded = true
        // Optimistic; the next refresh drops back to `needsAuth` if it did not take.
        hasSignedIn = true
    }
}
