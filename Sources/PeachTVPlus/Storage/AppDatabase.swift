import Foundation
import GRDB

/// Fabrique de la base de **cache catalogue** (équivalent Room côté Android).
///
/// - Sur disque : `Application Support/catalogue.sqlite`, **exclu de la sauvegarde
///   iCloud** (`isExcludedFromBackup`, cf. `docs/security.md §5.3`).
/// - En mémoire : pour les tests et aperçus.
///
/// Migrations **strictement additives** (`DatabaseMigrator`, jamais de drop&recreate) :
/// on ne perd jamais favoris ni reprises de lecture. On **ne** règle **pas**
/// `eraseDatabaseOnSchemaChange` (comportement release). Voir `docs/PORT-SPEC.md §4`.
enum AppDatabase {

    static let catalogFileName = "catalogue.sqlite"

    /// Base de catalogue persistante (Application Support), hors sauvegarde iCloud.
    static func catalogStore() throws -> CatalogStore {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        var url = support.appendingPathComponent(catalogFileName)

        let queue = try DatabaseQueue(path: url.path)
        try migrator.migrate(queue)

        // H2 (port Android) : la base de cache DOIT sortir de la sauvegarde iCloud.
        // Best-effort : un échec d'exclusion ne doit pas empêcher l'app de démarrer.
        try? url.excludeFromBackup()

        return CatalogStore(writer: queue)
    }

    /// Base **en mémoire** — tests, previews. Aucune écriture disque.
    static func inMemoryStore() throws -> CatalogStore {
        let queue = try DatabaseQueue()   // in-memory
        try migrator.migrate(queue)
        return CatalogStore(writer: queue)
    }

    /// Store des téléchargements adossé à **la même base** que le catalogue (un seul fichier).
    /// ⚠️ Ouvre sa propre connexion : en production (M5), `AppContainer` partagera **un seul**
    /// writer pour construire `CatalogStore` **et** `DownloadStore` (éviter deux connexions
    /// concurrentes au même fichier). Ici (M4), aucun câblage runtime ne les ouvre ensemble.
    static func downloadStore() throws -> DownloadStore {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        var url = support.appendingPathComponent(catalogFileName)
        let queue = try DatabaseQueue(path: url.path)
        try migrator.migrate(queue)
        try? url.excludeFromBackup()
        return DownloadStore(writer: queue)
    }

    /// Store des téléchargements **en mémoire** — tests.
    static func inMemoryDownloadStore() throws -> DownloadStore {
        let queue = try DatabaseQueue()
        try migrator.migrate(queue)
        return DownloadStore(writer: queue)
    }

    /// Migrateur partagé. Chaque étape est **additive** et porte un identifiant stable.
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1-catalogue") { db in
            // --- Catégories : clé composée (type, id), mappe `categories` (Room) ---
            try db.create(table: "categories") { t in
                t.column("contentType", .text).notNull()
                t.column("categoryId", .text).notNull()
                t.column("name", .text).notNull()
                t.primaryKey(["contentType", "categoryId"])
            }

            // --- Chaînes Live ---
            try db.create(table: "live_channels") { t in
                t.primaryKey("streamId", .text)
                t.column("name", .text).notNull()
                t.column("iconURL", .text)
                t.column("categoryId", .text).indexed()
                t.column("epgChannelId", .text)
                t.column("hasArchive", .boolean).notNull().defaults(to: false)
            }

            // --- Films ---
            try db.create(table: "movies") { t in
                t.primaryKey("streamId", .text)
                t.column("name", .text).notNull()
                t.column("posterURL", .text)
                t.column("categoryId", .text).indexed()
                t.column("containerExtension", .text)
                t.column("rating", .double)
            }

            // --- Séries ---
            try db.create(table: "series") { t in
                t.primaryKey("seriesId", .text)
                t.column("name", .text).notNull()
                t.column("posterURL", .text)
                t.column("categoryId", .text).indexed()
                t.column("rating", .double)
            }

            // --- Positions de lecture (reprise VOD) ---
            try db.create(table: "playback_positions") { t in
                t.primaryKey("contentKey", .text)       // "movie:123" / "episode:456"
                t.column("contentType", .text).notNull()
                t.column("positionSeconds", .integer).notNull()
                t.column("durationSeconds", .integer)
                t.column("title", .text)                // dénormalisé (affiché sans le cache)
                t.column("posterURL", .text)
                t.column("updatedAt", .double).notNull().indexed()
            }

            // --- Favoris : SCOPÉS par `playlistId` (survivent à la bascule de liste) ---
            try db.create(table: "favorites") { t in
                t.column("playlistId", .text).notNull()
                t.column("contentType", .text).notNull()
                t.column("itemId", .text).notNull()
                t.column("name", .text)                 // dénormalisé
                t.column("posterURL", .text)
                t.column("addedAt", .double).notNull().indexed()
                t.primaryKey(["playlistId", "contentType", "itemId"])
            }

            // --- Index acteurs (recherche par acteur) : colonne `castNames`, PAS `cast` ---
            try db.create(table: "cast_index") { t in
                t.primaryKey("itemKey", .text)
                t.column("castNames", .text).notNull()
            }

            // --- Chaînes masquées : SCOPÉES par `playlistId` ---
            try db.create(table: "hidden_channels") { t in
                t.column("playlistId", .text).notNull()
                t.column("streamId", .text).notNull()
                t.primaryKey(["playlistId", "streamId"])
            }

            // --- FTS5 synchronisées (recherche par titre — jamais un filtre mémoire) ---
            // `synchronize(withTable:)` crée les triggers qui tiennent l'index à jour.
            try db.create(virtualTable: "live_channels_ft", using: FTS5()) { t in
                t.synchronize(withTable: "live_channels")
                t.column("name")
            }
            try db.create(virtualTable: "movies_ft", using: FTS5()) { t in
                t.synchronize(withTable: "movies")
                t.column("name")
            }
            try db.create(virtualTable: "series_ft", using: FTS5()) { t in
                t.synchronize(withTable: "series")
                t.column("name")
            }
        }

        // M4 — table des téléchargements. Étape ADDITIVE (jamais toucher v1).
        migrator.registerMigration("v2-downloads") { db in
            try db.create(table: "downloads") { t in
                t.primaryKey("contentKey", .text)   // "movie:123" / "episode:456"
                t.column("contentType", .text).notNull()
                t.column("playlistId", .text).notNull().indexed()
                t.column("title", .text).notNull()
                // URL de flux MASQUÉE (__cred__) — jamais d'identifiant persisté sur disque.
                t.column("maskedURL", .text).notNull()
                t.column("ext", .text).notNull()
                t.column("localPath", .text)        // nom 100% local (anti path-traversal)
                t.column("status", .text).notNull()
                t.column("percent", .double).notNull().defaults(to: 0)
                t.column("bytesDownloaded", .integer).notNull().defaults(to: 0)
                t.column("totalBytes", .integer)
                t.column("resumeData", .blob)        // reprise HTTP Range
                t.column("errorMessage", .text)
                t.column("updatedAt", .double).notNull().indexed()
            }
        }

        return migrator
    }
}
