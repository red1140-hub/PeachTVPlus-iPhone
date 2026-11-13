import XCTest
@testable import PeachTVPlus

/// Allowlist de schémas (`URLGuard`) + consentement HTTP par serveur (`CleartextConsent`).
final class SecurityGuardsTests: XCTestCase {

    private func isolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test.\(UUID().uuidString)")!
    }

    // MARK: - URLGuard

    func testURLGuardAllowsOnlyHttpHttpsWithHost() {
        XCTAssertTrue(URLGuard.isPlayable("http://s.com/live/1.ts"))
        XCTAssertTrue(URLGuard.isPlayable("https://s.com/movie/3.mp4"))
        XCTAssertFalse(URLGuard.isPlayable("file:///etc/passwd"))
        XCTAssertFalse(URLGuard.isPlayable("data:text/plain,bonjour"))
        XCTAssertFalse(URLGuard.isPlayable("ftp://s.com/x"))
        XCTAssertFalse(URLGuard.isPlayable("javascript:alert(1)"))
    }

    // MARK: - CleartextConsent

    func testHttpsAlwaysAllowed() {
        let consent = CleartextConsent(defaults: isolatedDefaults())
        XCTAssertTrue(consent.maySendCredentials(to: URL(string: "https://s.com/player_api.php")!))
    }

    func testHttpBlockedUntilConsentThenRevocable() {
        let consent = CleartextConsent(defaults: isolatedDefaults())
        let url = URL(string: "http://s.com/player_api.php")!

        XCTAssertFalse(consent.maySendCredentials(to: url))   // pas de consentement → bloqué
        consent.grant(host: "s.com")
        XCTAssertTrue(consent.maySendCredentials(to: url))    // consenti pour ce serveur
        consent.revoke(host: "s.com")
        XCTAssertFalse(consent.maySendCredentials(to: url))   // révocable
    }

    func testConsentIsPerHost() {
        let consent = CleartextConsent(defaults: isolatedDefaults())
        consent.grant(host: "a.com")
        XCTAssertTrue(consent.maySendCredentials(to: URL(string: "http://a.com/x")!))
        XCTAssertFalse(consent.maySendCredentials(to: URL(string: "http://b.com/x")!)) // pas b.com
    }

    func testNonHttpSchemeNeverSendsCredentials() {
        let consent = CleartextConsent(defaults: isolatedDefaults())
        XCTAssertFalse(consent.maySendCredentials(to: URL(string: "ftp://s.com/x")!))
    }
}
