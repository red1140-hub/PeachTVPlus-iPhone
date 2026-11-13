import XCTest
@testable import PeachTVPlus

final class XtreamCredentialsTests: XCTestCase {

    func testNormalizeBareHostWithPort() {
        let c = XtreamCredentials.normalize(server: "serveur.com:8080", username: "u", password: "p")
        XCTAssertEqual(c?.serverUrl, "http://serveur.com:8080")
        XCTAssertEqual(c?.isSecure, false)
    }

    func testNormalizeHttpsTrailingSlash() {
        let c = XtreamCredentials.normalize(server: "https://serveur.com/", username: "u", password: "p")
        XCTAssertEqual(c?.serverUrl, "https://serveur.com")
        XCTAssertEqual(c?.isSecure, true)
    }

    func testNormalizeFullPlayerApiUrlReducedToOrigin() {
        let raw = "http://serveur.com:25461/player_api.php?username=x&password=y"
        let c = XtreamCredentials.normalize(server: raw, username: "u", password: "p")
        XCTAssertEqual(c?.serverUrl, "http://serveur.com:25461")
    }

    func testNormalizeTrimsWhitespaceInFields() {
        let c = XtreamCredentials.normalize(server: "  serveur.com  ", username: "  bob ", password: " pw ")
        XCTAssertEqual(c?.serverUrl, "http://serveur.com")
        XCTAssertEqual(c?.username, "bob")
        XCTAssertEqual(c?.password, "pw")
    }

    func testNormalizeReturnsNilWithoutHost() {
        XCTAssertNil(XtreamCredentials.normalize(server: "   ", username: "u", password: "p"))
    }

    func testDescriptionHidesPassword() {
        let c = XtreamCredentials(serverUrl: "http://s.com", username: "bob", password: "secret")
        XCTAssertFalse(c.description.contains("secret"))
        XCTAssertTrue(c.description.contains("bob"))
    }

    func testHostExtraction() {
        let c = XtreamCredentials(serverUrl: "http://serveur.com:8080", username: "u", password: "p")
        XCTAssertEqual(c.host, "serveur.com")
    }
}
