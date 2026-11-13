import XCTest
@testable import PeachTVPlus

/// Vérifie les **hooks de cache** du repository (M2) : bascule de liste → vidage du cache en
/// gardant les favoris ; retrait d'une liste → purge de ses favoris ; dernière liste retirée
/// → effacement total + store vidé (loi 25).
@MainActor
final class XtreamRepositoryCatalogTests: XCTestCase {

    private let credA = XtreamCredentials(serverUrl: "http://a.com", username: "u", password: "p")
    private let credB = XtreamCredentials(serverUrl: "http://b.com", username: "u", password: "p")

    private func movie(_ id: String) -> Movie {
        Movie(id: id, name: "Film\(id)", posterURL: nil, categoryId: "c",
              containerExtension: "mp4", rating: nil)
    }

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testActivatingPlaylistClearsCatalogButKeepsFavorites() throws {
        let catalog = try AppDatabase.inMemoryStore()
        let repo = XtreamRepository(session: MockURLProtocol.session(),
                                    store: InMemoryPlaylistStore(), catalog: catalog)
        let idA = Playlist(credentials: credA).id
        try catalog.saveMovies([movie("1")])
        try catalog.addFavorite(playlistId: idA, contentType: .vod, itemId: "1",
                               name: "Film1", posterURL: nil)

        repo.addOrActivate(credA)   // nouvelle source active → resetForSourceChange → clearCatalog

        XCTAssertTrue(try catalog.movies().isEmpty)                                    // cache vidé
        XCTAssertEqual(try catalog.favorites(playlistId: idA, contentType: .vod).count, 1) // gardé
    }

    func testRemovingPlaylistPurgesItsFavoritesOnly() throws {
        let catalog = try AppDatabase.inMemoryStore()
        let repo = XtreamRepository(session: MockURLProtocol.session(),
                                    store: InMemoryPlaylistStore(), catalog: catalog)
        let idA = Playlist(credentials: credA).id
        let idB = Playlist(credentials: credB).id
        repo.addOrActivate(credA)
        repo.addOrActivate(credB)
        try catalog.addFavorite(playlistId: idA, contentType: .vod, itemId: "1", name: nil, posterURL: nil)
        try catalog.addFavorite(playlistId: idB, contentType: .vod, itemId: "2", name: nil, posterURL: nil)

        repo.removePlaylist(idA)

        XCTAssertTrue(try catalog.favorites(playlistId: idA, contentType: .vod).isEmpty)       // purgé
        XCTAssertEqual(try catalog.favorites(playlistId: idB, contentType: .vod).count, 1)     // intact
        XCTAssertEqual(repo.activeCredentials, credB)
    }

    func testRemovingLastPlaylistClearsEverythingAndStore() throws {
        let catalog = try AppDatabase.inMemoryStore()
        let store = InMemoryPlaylistStore()
        let repo = XtreamRepository(session: MockURLProtocol.session(), store: store, catalog: catalog)
        let idA = Playlist(credentials: credA).id
        repo.addOrActivate(credA)
        try catalog.saveMovies([movie("1")])
        try catalog.addFavorite(playlistId: idA, contentType: .vod, itemId: "1", name: nil, posterURL: nil)

        repo.removePlaylist(idA)   // dernière liste → clearAll + store.clear()

        XCTAssertTrue(try catalog.movies().isEmpty)
        XCTAssertTrue(try catalog.favorites(playlistId: idA, contentType: .vod).isEmpty)
        XCTAssertFalse(repo.isLoggedIn)
        XCTAssertTrue(store.load().items.isEmpty)
    }
}
