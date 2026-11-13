import XCTest
@testable import PeachTVPlus

/// Tests du cache GRDB en **base mémoire** (aucune écriture disque, exécutables en CI).
final class CatalogStoreTests: XCTestCase {

    private func makeStore() throws -> CatalogStore {
        try AppDatabase.inMemoryStore()
    }

    private func movie(_ id: String, _ name: String, category: String = "c1") -> Movie {
        Movie(id: id, name: name, posterURL: nil, categoryId: category,
              containerExtension: "mp4", rating: nil)
    }

    // MARK: - Écriture / lecture / pagination

    func testSaveAndFetchMoviesByCategory() throws {
        let store = try makeStore()
        try store.saveMovies([
            movie("1", "Alpha", category: "c1"),
            movie("2", "Bravo", category: "c1"),
            movie("3", "Charlie", category: "c2"),
        ])
        let c1 = try store.movies(categoryId: "c1")
        XCTAssertEqual(c1.map(\.id).sorted(), ["1", "2"])
        let all = try store.movies()
        XCTAssertEqual(all.count, 3)
    }

    func testMoviesPagination() throws {
        let store = try makeStore()
        try store.saveMovies((0..<10).map { movie("\($0)", String(format: "Film%02d", $0)) })
        let page1 = try store.movies(limit: 4, offset: 0)
        let page2 = try store.movies(limit: 4, offset: 4)
        XCTAssertEqual(page1.count, 4)
        XCTAssertEqual(page2.count, 4)
        XCTAssertTrue(Set(page1.map(\.id)).isDisjoint(with: Set(page2.map(\.id))))
    }

    func testUpsertReplacesOnSameId() throws {
        let store = try makeStore()
        try store.saveMovies([movie("1", "Avant")])
        try store.saveMovies([movie("1", "Après")])
        let all = try store.movies()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.name, "Après")
    }

    // MARK: - Recherche FTS5

    func testSearchMoviesByTitleToken() throws {
        let store = try makeStore()
        try store.saveMovies([movie("1", "Star Wars"), movie("2", "The Matrix")])
        let hitsStar = try store.searchMovies("star")      // insensible à la casse (unicode61)
        XCTAssertEqual(hitsStar.map(\.id), ["1"])
        let hitsMatrix = try store.searchMovies("matrix")
        XCTAssertEqual(hitsMatrix.map(\.id), ["2"])
        XCTAssertTrue(try store.searchMovies("inexistant").isEmpty)
        XCTAssertTrue(try store.searchMovies("   ").isEmpty) // pattern vide → []
    }

    // MARK: - Invalidation du cache : garde favoris + masquées

    func testClearCatalogKeepsFavoritesAndHidden() throws {
        let store = try makeStore()
        try store.saveMovies([movie("1", "Alpha")])
        try store.addFavorite(playlistId: "A", contentType: .vod, itemId: "1",
                              name: "Alpha", posterURL: nil)
        try store.hide(playlistId: "A", streamId: "9")

        try store.clearCatalog()

        XCTAssertTrue(try store.movies().isEmpty)                       // cache vidé
        XCTAssertEqual(try store.favorites(playlistId: "A", contentType: .vod).count, 1)
        XCTAssertEqual(try store.hiddenStreamIds(playlistId: "A"), ["9"]) // conservés
    }

    // MARK: - Isolation par playlistId

    func testFavoritesScopedByPlaylist() throws {
        let store = try makeStore()
        try store.addFavorite(playlistId: "A", contentType: .vod, itemId: "1", name: nil, posterURL: nil)
        try store.addFavorite(playlistId: "B", contentType: .vod, itemId: "2", name: nil, posterURL: nil)

        XCTAssertTrue(try store.isFavorite(playlistId: "A", contentType: .vod, itemId: "1"))
        XCTAssertFalse(try store.isFavorite(playlistId: "B", contentType: .vod, itemId: "1"))
        XCTAssertEqual(try store.favorites(playlistId: "A", contentType: .vod).map(\.itemId), ["1"])
        XCTAssertEqual(try store.favorites(playlistId: "B", contentType: .vod).map(\.itemId), ["2"])
    }

    func testHiddenScopedByPlaylist() throws {
        let store = try makeStore()
        try store.hide(playlistId: "A", streamId: "1")
        try store.hide(playlistId: "B", streamId: "2")
        XCTAssertEqual(try store.hiddenStreamIds(playlistId: "A"), ["1"])
        XCTAssertEqual(try store.hiddenStreamIds(playlistId: "B"), ["2"])
        try store.restoreAllHidden(playlistId: "A")
        XCTAssertTrue(try store.hiddenStreamIds(playlistId: "A").isEmpty)
        XCTAssertEqual(try store.hiddenStreamIds(playlistId: "B"), ["2"])
    }

    func testPurgePlaylistRemovesOnlyThatPlaylist() throws {
        let store = try makeStore()
        try store.addFavorite(playlistId: "A", contentType: .vod, itemId: "1", name: nil, posterURL: nil)
        try store.hide(playlistId: "A", streamId: "9")
        try store.addFavorite(playlistId: "B", contentType: .vod, itemId: "2", name: nil, posterURL: nil)

        try store.purgePlaylist("A")

        XCTAssertTrue(try store.favorites(playlistId: "A", contentType: .vod).isEmpty)
        XCTAssertTrue(try store.hiddenStreamIds(playlistId: "A").isEmpty)
        XCTAssertEqual(try store.favorites(playlistId: "B", contentType: .vod).map(\.itemId), ["2"])
    }

    func testClearAllWipesEverything() throws {
        let store = try makeStore()
        try store.saveMovies([movie("1", "Alpha")])
        try store.addFavorite(playlistId: "A", contentType: .vod, itemId: "1", name: nil, posterURL: nil)
        try store.hide(playlistId: "A", streamId: "9")

        try store.clearAll()

        XCTAssertTrue(try store.movies().isEmpty)
        XCTAssertTrue(try store.favorites(playlistId: "A", contentType: .vod).isEmpty)
        XCTAssertTrue(try store.hiddenStreamIds(playlistId: "A").isEmpty)
    }

    // MARK: - Positions de lecture

    func testPlaybackPositionRoundTripAndRecent() throws {
        let store = try makeStore()
        try store.savePosition(PlaybackPositionRecord(
            contentKey: "movie:1", contentType: "vod", positionSeconds: 120,
            durationSeconds: 6000, title: "Alpha", posterURL: nil, updatedAt: 100))
        try store.savePosition(PlaybackPositionRecord(
            contentKey: "movie:2", contentType: "vod", positionSeconds: 30,
            durationSeconds: 6000, title: "Bravo", posterURL: nil, updatedAt: 200))

        XCTAssertEqual(try store.position(contentKey: "movie:1")?.positionSeconds, 120)
        // Plus récent d'abord (updatedAt desc).
        XCTAssertEqual(try store.recentPositions().map(\.contentKey), ["movie:2", "movie:1"])
    }
}
