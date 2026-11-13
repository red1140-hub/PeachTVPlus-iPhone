import Foundation
import GRDB

// MARK: - Enregistrements GRDB (mappent les tables Room ~1:1)
//
// Types valeurs internes → Sendable implicite. Conversions depuis/vers les modèles du
// domaine (`Model/DomainModels.swift`) pour que le reste de l'app ignore GRDB.

struct CategoryRecord: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName = "categories"
    var contentType: String
    var categoryId: String
    var name: String

    init(contentType: String, categoryId: String, name: String) {
        self.contentType = contentType; self.categoryId = categoryId; self.name = name
    }
    init(_ c: Category) {
        self.init(contentType: c.contentType.rawValue, categoryId: c.id, name: c.name)
    }
    var domain: Category? {
        guard let type = ContentType(rawValue: contentType) else { return nil }
        return Category(id: categoryId, name: name, contentType: type)
    }
}

struct LiveChannelRecord: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName = "live_channels"
    var streamId: String
    var name: String
    var iconURL: String?
    var categoryId: String?
    var epgChannelId: String?
    var hasArchive: Bool

    init(_ c: LiveChannel) {
        streamId = c.id; name = c.name; iconURL = c.iconURL
        categoryId = c.categoryId; epgChannelId = c.epgChannelId; hasArchive = c.hasArchive
    }
    var domain: LiveChannel {
        LiveChannel(id: streamId, name: name, iconURL: iconURL,
                    categoryId: categoryId, epgChannelId: epgChannelId, hasArchive: hasArchive)
    }
}

struct MovieRecord: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName = "movies"
    var streamId: String
    var name: String
    var posterURL: String?
    var categoryId: String?
    var containerExtension: String?
    var rating: Double?

    init(_ m: Movie) {
        streamId = m.id; name = m.name; posterURL = m.posterURL
        categoryId = m.categoryId; containerExtension = m.containerExtension; rating = m.rating
    }
    var domain: Movie {
        Movie(id: streamId, name: name, posterURL: posterURL, categoryId: categoryId,
              containerExtension: containerExtension, rating: rating)
    }
}

struct SeriesRecord: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName = "series"
    var seriesId: String
    var name: String
    var posterURL: String?
    var categoryId: String?
    var rating: Double?

    init(_ s: Series) {
        seriesId = s.id; name = s.name; posterURL = s.posterURL
        categoryId = s.categoryId; rating = s.rating
    }
    var domain: Series {
        Series(id: seriesId, name: name, posterURL: posterURL, categoryId: categoryId, rating: rating)
    }
}

/// Position de lecture pour la reprise VOD (table `playback_positions`).
struct PlaybackPositionRecord: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName = "playback_positions"
    var contentKey: String          // "movie:123" / "episode:456"
    var contentType: String
    var positionSeconds: Int
    var durationSeconds: Int?
    var title: String?
    var posterURL: String?
    var updatedAt: Double           // timeIntervalSince1970
}

/// Favori — **scopé par `playlistId`** (clé primaire composée avec `contentType` + `itemId`).
struct FavoriteRecord: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName = "favorites"
    var playlistId: String
    var contentType: String
    var itemId: String
    var name: String?
    var posterURL: String?
    var addedAt: Double
}

/// Index acteur→contenu (recherche par acteur). Colonne **`castNames`** (pas `cast`,
/// mot réservé SQL — leçon Android reportée).
struct CastIndexRecord: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName = "cast_index"
    var itemKey: String
    var castNames: String
}

/// Chaîne masquée — **scopée par `playlistId`**.
struct HiddenChannelRecord: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName = "hidden_channels"
    var playlistId: String
    var streamId: String
}
