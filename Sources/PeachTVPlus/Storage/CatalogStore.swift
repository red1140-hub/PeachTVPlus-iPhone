import Foundation
import GRDB

/// Accès au cache catalogue (lectures paginées, recherche FTS, favoris/masquées scopés
/// par `playlistId`, invalidation à la bascule de liste). Un seul écrivain pour `Storage/`.
///
/// ⚠️ API **synchrone** (bloque l'appelant le temps de l'I/O SQLite). Suffisant pour M2 :
/// il n'y a pas encore d'UI. **M5** déportera les appels hors du main actor (GRDB expose
/// aussi `try await writer.write {…}`). Voir `docs/PORT-SPEC.md §4`.
struct CatalogStore {
    let writer: DatabaseWriter

    // MARK: - Écriture du catalogue (upsert par lots, 1 transaction)

    func saveCategories(_ categories: [Category]) throws {
        try writer.write { db in
            for c in categories { try CategoryRecord(c).insert(db, onConflict: .replace) }
        }
    }

    func saveLiveChannels(_ channels: [LiveChannel]) throws {
        try writer.write { db in
            for c in channels { try LiveChannelRecord(c).insert(db, onConflict: .replace) }
        }
    }

    func saveMovies(_ movies: [Movie]) throws {
        try writer.write { db in
            for m in movies { try MovieRecord(m).insert(db, onConflict: .replace) }
        }
    }

    func saveSeries(_ series: [Series]) throws {
        try writer.write { db in
            for s in series { try SeriesRecord(s).insert(db, onConflict: .replace) }
        }
    }

    // MARK: - Lectures paginées

    func categories(type: ContentType) throws -> [Category] {
        try writer.read { db in
            try CategoryRecord
                .filter(Column("contentType") == type.rawValue)
                .order(Column("name"))
                .fetchAll(db)
                .compactMap(\.domain)
        }
    }

    func liveChannels(categoryId: String? = nil, limit: Int = 100, offset: Int = 0) throws -> [LiveChannel] {
        try writer.read { db in
            var request = LiveChannelRecord.all()
            if let categoryId { request = request.filter(Column("categoryId") == categoryId) }
            return try request.order(Column("name")).limit(limit, offset: offset).fetchAll(db).map(\.domain)
        }
    }

    func movies(categoryId: String? = nil, limit: Int = 100, offset: Int = 0) throws -> [Movie] {
        try writer.read { db in
            var request = MovieRecord.all()
            if let categoryId { request = request.filter(Column("categoryId") == categoryId) }
            return try request.order(Column("name")).limit(limit, offset: offset).fetchAll(db).map(\.domain)
        }
    }

    func series(categoryId: String? = nil, limit: Int = 100, offset: Int = 0) throws -> [Series] {
        try writer.read { db in
            var request = SeriesRecord.all()
            if let categoryId { request = request.filter(Column("categoryId") == categoryId) }
            return try request.order(Column("name")).limit(limit, offset: offset).fetchAll(db).map(\.domain)
        }
    }

    // MARK: - Recherche FTS5 (par titre ; jamais un filtre mémoire)

    func searchLiveChannels(_ query: String, limit: Int = 50, offset: Int = 0) throws -> [LiveChannel] {
        guard let pattern = FTS5Pattern(matchingAllTokensIn: query) else { return [] }
        return try writer.read { db in
            try LiveChannelRecord.all().matching(pattern)
                .order(Column("name")).limit(limit, offset: offset).fetchAll(db).map(\.domain)
        }
    }

    func searchMovies(_ query: String, limit: Int = 50, offset: Int = 0) throws -> [Movie] {
        guard let pattern = FTS5Pattern(matchingAllTokensIn: query) else { return [] }
        return try writer.read { db in
            try MovieRecord.all().matching(pattern)
                .order(Column("name")).limit(limit, offset: offset).fetchAll(db).map(\.domain)
        }
    }

    func searchSeries(_ query: String, limit: Int = 50, offset: Int = 0) throws -> [Series] {
        guard let pattern = FTS5Pattern(matchingAllTokensIn: query) else { return [] }
        return try writer.read { db in
            try SeriesRecord.all().matching(pattern)
                .order(Column("name")).limit(limit, offset: offset).fetchAll(db).map(\.domain)
        }
    }

    // MARK: - Invalidation du cache (bascule de liste / epoch)

    /// Vide **uniquement** le cache catalogue (catégories, chaînes, films, séries, positions,
    /// index acteurs). **Conserve** favoris et chaînes masquées (scopés `playlistId`).
    /// Appelé à chaque changement de source active. Les triggers FTS5 se mettent à jour seuls.
    func clearCatalog() throws {
        try writer.write { db in
            _ = try CategoryRecord.deleteAll(db)
            _ = try LiveChannelRecord.deleteAll(db)
            _ = try MovieRecord.deleteAll(db)
            _ = try SeriesRecord.deleteAll(db)
            _ = try PlaybackPositionRecord.deleteAll(db)
            _ = try CastIndexRecord.deleteAll(db)
        }
    }

    // MARK: - Favoris (scopés par `playlistId`)

    func addFavorite(playlistId: String, contentType: ContentType, itemId: String,
                     name: String?, posterURL: String?, at date: Date = Date()) throws {
        let record = FavoriteRecord(playlistId: playlistId, contentType: contentType.rawValue,
                                    itemId: itemId, name: name, posterURL: posterURL,
                                    addedAt: date.timeIntervalSince1970)
        try writer.write { db in try record.insert(db, onConflict: .replace) }
    }

    func removeFavorite(playlistId: String, contentType: ContentType, itemId: String) throws {
        try writer.write { db in
            _ = try FavoriteRecord
                .filter(Column("playlistId") == playlistId)
                .filter(Column("contentType") == contentType.rawValue)
                .filter(Column("itemId") == itemId)
                .deleteAll(db)
        }
    }

    func isFavorite(playlistId: String, contentType: ContentType, itemId: String) throws -> Bool {
        try writer.read { db in
            try FavoriteRecord
                .filter(Column("playlistId") == playlistId)
                .filter(Column("contentType") == contentType.rawValue)
                .filter(Column("itemId") == itemId)
                .fetchCount(db) > 0
        }
    }

    func favorites(playlistId: String, contentType: ContentType) throws -> [FavoriteRecord] {
        try writer.read { db in
            try FavoriteRecord
                .filter(Column("playlistId") == playlistId)
                .filter(Column("contentType") == contentType.rawValue)
                .order(Column("addedAt").desc)
                .fetchAll(db)
        }
    }

    // MARK: - Chaînes masquées (scopées par `playlistId`)

    func hide(playlistId: String, streamId: String) throws {
        let record = HiddenChannelRecord(playlistId: playlistId, streamId: streamId)
        try writer.write { db in try record.insert(db, onConflict: .replace) }
    }

    func unhide(playlistId: String, streamId: String) throws {
        try writer.write { db in
            _ = try HiddenChannelRecord
                .filter(Column("playlistId") == playlistId)
                .filter(Column("streamId") == streamId)
                .deleteAll(db)
        }
    }

    func hiddenStreamIds(playlistId: String) throws -> Set<String> {
        try writer.read { db in
            let rows = try HiddenChannelRecord.filter(Column("playlistId") == playlistId).fetchAll(db)
            return Set(rows.map(\.streamId))
        }
    }

    func restoreAllHidden(playlistId: String) throws {
        try writer.write { db in
            _ = try HiddenChannelRecord.filter(Column("playlistId") == playlistId).deleteAll(db)
        }
    }

    // MARK: - Positions de lecture (reprise VOD)

    func savePosition(_ record: PlaybackPositionRecord) throws {
        try writer.write { db in try record.insert(db, onConflict: .replace) }
    }

    func position(contentKey: String) throws -> PlaybackPositionRecord? {
        try writer.read { db in try PlaybackPositionRecord.fetchOne(db, key: contentKey) }
    }

    func recentPositions(limit: Int = 20) throws -> [PlaybackPositionRecord] {
        try writer.read { db in
            try PlaybackPositionRecord.order(Column("updatedAt").desc).limit(limit).fetchAll(db)
        }
    }

    // MARK: - Suppression par liste / effacement total (loi 25)

    /// Retrait d'une liste : purge **ses** favoris et **ses** chaînes masquées.
    func purgePlaylist(_ playlistId: String) throws {
        try writer.write { db in
            _ = try FavoriteRecord.filter(Column("playlistId") == playlistId).deleteAll(db)
            _ = try HiddenChannelRecord.filter(Column("playlistId") == playlistId).deleteAll(db)
        }
    }

    /// Dernière liste retirée / déconnexion totale : efface **toute** la base (loi 25).
    func clearAll() throws {
        try writer.write { db in
            _ = try CategoryRecord.deleteAll(db)
            _ = try LiveChannelRecord.deleteAll(db)
            _ = try MovieRecord.deleteAll(db)
            _ = try SeriesRecord.deleteAll(db)
            _ = try PlaybackPositionRecord.deleteAll(db)
            _ = try CastIndexRecord.deleteAll(db)
            _ = try FavoriteRecord.deleteAll(db)
            _ = try HiddenChannelRecord.deleteAll(db)
        }
    }
}
