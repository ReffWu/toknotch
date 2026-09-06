import XCTest
@testable import Codenotch

/// What the settings row is allowed to offer.
///
/// "Allow access…" used to be shown for every keychain-backed provider,
/// unconditionally. That put a remedy on screen next to a perfectly working
/// account, and — because the same row looked identical when the remedy *was*
/// needed — gave no way to tell a button that had nothing to do from one that
/// was failing to do it.
@MainActor
final class ProviderSummaryTests: XCTestCase {

    /// A refusal reaches the row. It did not before: `ProviderSummary` carried
    /// no notion of one.
    func testARefusalReachesTheRow() async {
        let provider = SwitchableProvider(outcome: .failure(.accessDenied))
        let store = makeStore(provider)

        await store.refresh()

        XCTAssertTrue(store.providerSummaries.first?.wasRefusedAccess ?? false)
    }

    /// The case the first attempt at this got wrong.
    ///
    /// With a good reading already in hand, `supersedesHistory` keeps the old
    /// snapshot *and its status* through a refusal — on purpose, because the
    /// number is still true. Anything reading the refusal off the snapshot sees
    /// `.ok` and shows nothing, which is exactly what happened on screen.
    func testARefusalReachesTheRowEvenWithAGoodReadingInHand() async {
        let provider = SwitchableProvider(outcome: .success)
        let store = makeStore(provider)

        await store.refresh()
        XCTAssertFalse(store.providerSummaries.first?.wasRefusedAccess ?? true)
        // The snapshot deliberately keeps saying the reading is fine.
        provider.outcome = .failure(.accessDenied)

        await store.refresh()

        XCTAssertNotEqual(store.snapshots.first?.status, .accessDenied,
                          "the remembered reading should have survived the refusal")
        XCTAssertTrue(store.providerSummaries.first?.wasRefusedAccess ?? false,
                      "the row could not tell it had been refused")
    }

    /// And it clears as soon as macOS lets us back in, so the remedy stops being
    /// offered the moment it stops being needed.
    func testTheRemedyGoesAwayOnceAccessIsGrantedAgain() async {
        let provider = SwitchableProvider(outcome: .failure(.accessDenied))
        let store = makeStore(provider)

        await store.refresh()
        XCTAssertTrue(store.providerSummaries.first?.wasRefusedAccess ?? false)

        provider.outcome = .success
        await store.refresh()

        XCTAssertFalse(store.providerSummaries.first?.wasRefusedAccess ?? true,
                       "the button would have stayed on screen with nothing to fix")
    }

    /// Other failures are not refusals. `needsAuth` in particular has no
    /// keychain dialogue behind it to raise.
    func testOtherFailuresDoNotOfferTheAccessRemedy() async {
        for error in [UsageProviderError.needsAuth,
                      .badResponse(status: 500),
                      .rateLimited(retryAfter: 60)] {
            let store = makeStore(SwitchableProvider(outcome: .failure(error)))
            await store.refresh()
            XCTAssertFalse(store.providerSummaries.first?.wasRefusedAccess ?? true,
                           "\(error) was treated as a keychain refusal")
        }
    }

    /// Before the first fetch nothing has been refused, so nothing is offered.
    ///
    /// The store seeds its snapshots at init rather than leaving them absent, so
    /// the row must reach its verdict from an actual refusal and not from the
    /// mere presence — or absence — of a reading.
    func testWithoutAFetchTheRowOffersNothing() {
        let store = makeStore(SwitchableProvider(outcome: .failure(.accessDenied)))

        XCTAssertFalse(store.providerSummaries.first?.wasRefusedAccess ?? true,
                       "a remedy was offered before anything had failed")
    }

    // MARK: - Helpers

    private func makeStore(_ provider: SwitchableProvider) -> UsageStore {
        let name = "ProviderSummaryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return UsageStore(providers: [provider], archive: UsageArchive(defaults: defaults))
    }
}

/// A provider whose answer can be changed between refreshes, so a test can put
/// a good reading in the store's hands before taking access away.
private final class SwitchableProvider: UsageProvider, @unchecked Sendable {
    enum Outcome {
        case success
        case failure(UsageProviderError)
    }

    let id = "claude"
    let displayName = "Claude"
    let glyph = ProviderGlyph.claude
    var outcome: Outcome

    init(outcome: Outcome) { self.outcome = outcome }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        switch outcome {
        case .failure(let error):
            throw error
        case .success:
            return ProviderSnapshot(
                id: id, displayName: displayName, glyph: glyph,
                fidelity: .official, status: .ok,
                windows: [LimitWindow(id: "session", label: "Current session",
                                      usedFraction: 0.42,
                                      resetsAt: Date().addingTimeInterval(3600))]
            )
        }
    }
    func account() -> ProviderAccount? { nil }
    nonisolated var signInRoute: SignInRoute { .guidance("—") }
    func signOut() async {}
    func presentSignIn() {}
    nonisolated func forgetCachedCredential() {}
}
