import XCTest
@testable import PeachTVPlus

@MainActor
final class XtreamRepositoryTests: XCTestCase {

    private let credA = XtreamCredentials(serverUrl: "http://a.com", username: "u", password: "p")
    private let credB = XtreamCredentials(serverUrl: "http://b.com", username: "u", password: "p")

    private func makeRepo() -> XtreamRepository {
        XtreamRepository(session: MockURLProtocol.session(), store: InMemoryPlaylistStore())
    }

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    // MARK: - Login

    func testLoginSuccessActivatesPlaylist() async {
        MockURLProtocol.respond(json: #"{"user_info":{"auth":1,"status":"Active","username":"u"}}"#)
        let repo = makeRepo()
        let result = await repo.login(credA)
        guard case .success = result else { return XCTFail("attendu .success, obtenu \(result)") }
        XCTAssertTrue(repo.isLoggedIn)
        XCTAssertEqual(repo.activeCredentials, credA)
        XCTAssertEqual(repo.playlistEpoch, 1)
    }

    func testLoginInvalidCredentials() async {
        MockURLProtocol.respond(json: #"{"user_info":{"auth":0}}"#)
        let repo = makeRepo()
        let result = await repo.login(credA)
        XCTAssertEqual(result, .invalidCredentials)
        XCTAssertFalse(repo.isLoggedIn)
    }

    func testLoginExpired() async {
        MockURLProtocol.respond(json: #"{"user_info":{"auth":1,"status":"Expired"}}"#)
        let repo = makeRepo()
        XCTAssertEqual(await repo.login(credA), .expired)
    }

    func testLoginHttp401IsInvalidCredentials() async {
        MockURLProtocol.respond(statusCode: 401, json: "{}")
        let repo = makeRepo()
        XCTAssertEqual(await repo.login(credA), .invalidCredentials)
    }

    func testLoginHttp500IsNetworkError() async {
        MockURLProtocol.respond(statusCode: 500, json: "{}")
        let repo = makeRepo()
        guard case .networkError = await repo.login(credA) else { return XCTFail("attendu .networkError") }
    }

    func testLoginTransportFailureIsNetworkError() async {
        MockURLProtocol.fail(URLError(.notConnectedToInternet))
        let repo = makeRepo()
        guard case .networkError = await repo.login(credA) else { return XCTFail("attendu .networkError") }
        XCTAssertFalse(makeRepo().isLoggedIn)
    }

    // MARK: - Multi-listes (sans réseau)

    func testPlaylistSwitchingBumpsEpochAndKeepsIdentity() {
        let repo = makeRepo()

        repo.addOrActivate(credA)
        XCTAssertEqual(repo.playlistEpoch, 1)
        XCTAssertEqual(repo.activeCredentials, credA)

        // Ré-ajouter la même liste ne change pas la source → pas d'incrément.
        repo.addOrActivate(credA)
        XCTAssertEqual(repo.playlistEpoch, 1)
        XCTAssertEqual(repo.playlists.count, 1)

        // Nouvelle liste → bascule → epoch++.
        repo.addOrActivate(credB)
        XCTAssertEqual(repo.playlistEpoch, 2)
        XCTAssertEqual(repo.activeCredentials, credB)
        XCTAssertEqual(repo.playlists.count, 2)

        // Rebascule explicite.
        let idA = Playlist(credentials: credA).id
        repo.setActivePlaylist(idA)
        XCTAssertEqual(repo.playlistEpoch, 3)
        XCTAssertEqual(repo.activeCredentials, credA)

        // Retrait de la liste active → bascule sur l'autre + epoch++.
        repo.removePlaylist(idA)
        XCTAssertEqual(repo.playlistEpoch, 4)
        XCTAssertEqual(repo.activeCredentials, credB)
        XCTAssertEqual(repo.playlists.count, 1)
    }

    func testRemovingLastPlaylistLogsOut() {
        let repo = makeRepo()
        repo.addOrActivate(credA)
        repo.removePlaylist(Playlist(credentials: credA).id)
        XCTAssertFalse(repo.isLoggedIn)
        XCTAssertNil(repo.activeCredentials)
    }
}
