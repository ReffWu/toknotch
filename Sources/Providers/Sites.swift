import Foundation

/// The site-specific halves of `WebSessionProvider`.
enum Sites {
    static let perplexity = WebSessionProvider.Site(
        id: "perplexity",
        displayName: "Perplexity",
        glyph: .third,
        origin: URL(string: "https://www.perplexity.ai/")!,
        script: """
        const response = await fetch('/rest/rate-limit/all', {
            credentials: 'include',
            headers: { 'Accept': 'application/json' }
        });
        const text = await response.text();
        // `sources.source_to_limit` is a long tail of connector quotas with
        // nothing to do with model usage; drop it so the rest stays legible.
        let trimmed = text;
        try { const p = JSON.parse(text); delete p.sources; trimmed = JSON.stringify(p); } catch (_) {}
        return JSON.stringify({ status: response.status, body: trimmed });
        """,
        parse: PerplexityUsage.windows(fromJSON:)
    )

}
