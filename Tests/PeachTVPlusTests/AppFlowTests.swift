import XCTest
@testable import PeachTVPlus

/// Tests des pièces M5 vérifiables sans réseau ni appareil : construction d'URL de lecture,
/// coffre d'identifiants thread-safe, et branches **hors-ligne** du routage de session
/// (serveur invalide, garde-fou HTTP). Le câblage UI/runtime complet relève du QA M6.
@MainActor
final class AppFlowTests: XCTestCase {

    private func factory() -> XtreamURLFactory {
        XtreamURLFactory(credentials: XtreamCredentials(
            serverUrl: "http://host:8080", username: "user", password: "pass"))
    }

    // MARK: - PlaybackURLBuilder

    func testBuildLiveRequest() {
        let channel = LiveChannel(id: "12", name: "TVA", iconURL: nil,
                                  categoryId: "c1", epgChannelId: nil, hasArchive: true)
        let req = PlaybackURLBuilder.live(channel, factory: factory())
        XCTAssertEqual(req.url.absoluteString, "http://host:8080/live/user/pass/12.ts")
        XCTAssertEqual(req.title, "TVA")
        XCTAssertTrue(req.isLive)
    }

    func testBuildMovieRequestUsesContainerExtension() {
        let movie = Movie(id: "5", name: "Film", posterURL: nil, categoryId: nil,
                          containerExtension: "mkv", rating: nil)
        let req = PlaybackURLBuilder.movie(movie, factory: factory())
        XCTAssertEqual(req.url.absoluteString, "http://host:8080/movie/user/pass/5.mkv")
        XCTAssertFalse(req.isLive)
    }

    func testBuildMovieRequestFallsBackToMp4() {
        let movie = Movie(id: "7", name: "Film", posterURL: nil, categoryId: nil,
                          containerExtension: nil, rating: nil)
        let req = PlaybackURLBuilder.movie(movie, factory: factory())
        XCTAssertEqual(req.url.absoluteString, "http://host:8080/movie/user/pass/7.mp4")
    }

    func testBuildEpisodeRequest() {
        let ep = Episode(id: "9", title: "Pilote", seasonNumber: 1, episodeNumber: 2,
                         containerExtension: nil, durationSeconds: nil, posterURL: nil)
        let req = PlaybackURLBuilder.episode(ep, seriesName: "Ma Série", factory: factory())
        XCTAssertEqual(req.url.absoluteString, "http://host:8080/series/user/pass/9.mp4")
        XCTAssertEqual(req.title, "Ma Série")
        XCTAssertEqual(req.subtitle, "S1E2 · Pilote")
        XCTAssertFalse(req.isLive)
    }

    // MARK: - CredentialsVault

    func testCredentialsVaultLookup() {
        let creds = XtreamCredentials(serverUrl: "http://h", username: "u", password: "p")
        let playlist = Playlist(credentials: creds)
        let vault = CredentialsVault()
        vault.set([playlist])
        XCTAssertEqual(vault.credentials(for: playlist.id), creds)
        XCTAssertNil(vault.credentials(for: "inconnu"))
        vault.set([])
        XCTAssertNil(vault.credentials(for: playlist.id))
    }

    // MARK: - SessionViewModel (branches hors-ligne)

    private func makeSession() throws -> SessionViewModel {
        let stores = try AppDatabase.sharedInMemory()
        let container = AppContainer(catalog: stores.catalog, downloads: stores.downloads)
        return SessionViewModel(container: container)
    }

    func testLoginRejectsInvalidServer() async throws {
        let session = try makeSession()
        let ok = await session.login(server: "   ", username: "u", password: "p")
        XCTAssertFalse(ok)
        XCTAssertNotNil(session.errorMessage)
        XCTAssertFalse(session.isLoggedIn)
    }

    func testLoginRequiresCleartextConsentForHTTP() async throws {
        let session = try makeSession()
        // Serveur HTTP non consenti → bloqué AVANT tout envoi réseau.
        let ok = await session.login(server: "http://example.test:8080", username: "u", password: "p")
        XCTAssertFalse(ok)
        XCTAssertEqual(session.pendingCleartextHost, "example.test")
        XCTAssertFalse(session.isLoggedIn)
    }
}
