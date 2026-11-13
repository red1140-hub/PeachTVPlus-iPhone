import Foundation
import GRDB

/// Ligne de la table `downloads`. **Aucun secret sur disque** : `maskedURL` contient le
/// marqueur `__cred__`, les identifiants sont réinjectés en mémoire au (re)lancement de la
/// tâche (garde-fou d'hôte, `XtreamURLFactory.reinjectCredentials`). Voir `docs/PORT-SPEC.md §6`.
struct DownloadRecord: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName = "downloads"

    var contentKey: String          // "movie:123" / "episode:456"
    var contentType: String
    var playlistId: String
    var title: String
    var maskedURL: String           // forme __cred__ (jamais d'identifiant persisté)
    var ext: String
    var localPath: String?
    var status: String              // DownloadStatus.rawValue
    var percent: Double
    var bytesDownloaded: Int
    var totalBytes: Int?
    var resumeData: Data?
    var errorMessage: String?
    var updatedAt: Double

    var downloadStatus: DownloadStatus { DownloadStatus(rawValue: status) ?? .failed }

    var uiState: DownloadUiState {
        DownloadUiState(contentKey: contentKey, title: title, status: downloadStatus, percent: percent)
    }
}
