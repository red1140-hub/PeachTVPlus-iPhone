import Foundation
import GRDB

/// Persistance de la file de téléchargements (table `downloads`). API synchrone (cf.
/// `CatalogStore` — déportée hors du main actor en M5).
struct DownloadStore {
    let writer: DatabaseWriter

    func upsert(_ record: DownloadRecord) throws {
        try writer.write { db in try record.insert(db, onConflict: .replace) }
    }

    func record(contentKey: String) throws -> DownloadRecord? {
        try writer.read { db in try DownloadRecord.fetchOne(db, key: contentKey) }
    }

    func all() throws -> [DownloadRecord] {
        try writer.read { db in
            try DownloadRecord.order(Column("updatedAt").desc).fetchAll(db)
        }
    }

    /// Téléchargements « vivants » (à relancer au démarrage) : en file, en cours ou en pause.
    func active() throws -> [DownloadRecord] {
        let live = [DownloadStatus.queued, .downloading, .paused].map(\.rawValue)
        return try writer.read { db in
            try DownloadRecord.filter(live.contains(Column("status")))
                .order(Column("updatedAt")).fetchAll(db)
        }
    }

    func completed() throws -> [DownloadRecord] {
        try writer.read { db in
            try DownloadRecord.filter(Column("status") == DownloadStatus.completed.rawValue)
                .order(Column("updatedAt").desc).fetchAll(db)
        }
    }

    // MARK: - Mutations ciblées (évitent de relire/réécrire tout l'enregistrement)

    func setStatus(contentKey: String, _ status: DownloadStatus, error: String? = nil,
                   at now: Double = Date().timeIntervalSince1970) throws {
        try writer.write { db in
            try db.execute(sql: """
                UPDATE downloads SET status = ?, errorMessage = ?, updatedAt = ? WHERE contentKey = ?
                """, arguments: [status.rawValue, error, now, contentKey])
        }
    }

    func setProgress(contentKey: String, percent: Double, bytes: Int, total: Int?,
                     at now: Double = Date().timeIntervalSince1970) throws {
        try writer.write { db in
            try db.execute(sql: """
                UPDATE downloads SET percent = ?, bytesDownloaded = ?, totalBytes = ?, updatedAt = ?
                WHERE contentKey = ?
                """, arguments: [percent, bytes, total, now, contentKey])
        }
    }

    func setResumeData(contentKey: String, _ data: Data?,
                       at now: Double = Date().timeIntervalSince1970) throws {
        try writer.write { db in
            try db.execute(sql: "UPDATE downloads SET resumeData = ?, updatedAt = ? WHERE contentKey = ?",
                           arguments: [data, now, contentKey])
        }
    }

    func setLocalPath(contentKey: String, _ path: String,
                      at now: Double = Date().timeIntervalSince1970) throws {
        try writer.write { db in
            try db.execute(sql: "UPDATE downloads SET localPath = ?, updatedAt = ? WHERE contentKey = ?",
                           arguments: [path, now, contentKey])
        }
    }

    func delete(contentKey: String) throws {
        try writer.write { db in
            _ = try DownloadRecord.filter(Column("contentKey") == contentKey).deleteAll(db)
        }
    }

    /// Retrait d'une liste de lecture → supprime ses téléchargements (loi 25).
    func purgePlaylist(_ playlistId: String) throws {
        try writer.write { db in
            _ = try DownloadRecord.filter(Column("playlistId") == playlistId).deleteAll(db)
        }
    }

    func clearAll() throws {
        try writer.write { db in _ = try DownloadRecord.deleteAll(db) }
    }
}
