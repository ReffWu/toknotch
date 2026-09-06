import Foundation

/// Accepts the language server's self-signed certificate — and only its.
///
/// Antigravity serves its local RPC over HTTPS with a certificate no authority
/// vouches for, so the system rightly refuses it. The exception is scoped as
/// tightly as it can be: loopback only, so nothing reached over a network is
/// ever trusted by this session. A blanket `NSAllowsArbitraryLoads` would have
/// been one line and would have weakened every other request the app makes.
final class LocalhostTrust: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition,
                                                  URLCredential?) -> Void) {
        let host = challenge.protectionSpace.host
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              host == "127.0.0.1" || host == "localhost" || host == "::1",
              let trust = challenge.protectionSpace.serverTrust
        else { return completionHandler(.performDefaultHandling, nil) }

        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
