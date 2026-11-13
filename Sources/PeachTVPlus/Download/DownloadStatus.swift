import Foundation

/// État persistant d'un téléchargement (port de `DownloadUiState` Android).
enum DownloadStatus: String, Codable, Equatable {
    case queued         // en file d'attente
    case downloading    // transfert en cours
    case paused         // en pause (reprise possible via resumeData)
    case completed      // terminé, lisible 100% hors-ligne
    case failed         // erreur (voir errorMessage)
    case removing       // suppression en cours (transitoire)
}

/// Vue agrégée pour l'UI, indexée par `contentKey`.
struct DownloadUiState: Equatable {
    let contentKey: String
    let title: String
    let status: DownloadStatus
    let percent: Double          // 0…1
}

/// **Bouton 6 états** (port de `DownloadButton`/`DownloadUiState`). `notDownloaded` = aucun
/// enregistrement. Couleur/icône/forme + label d'accessibilité dynamique. Voir `docs/PORT-SPEC.md §6`.
enum DownloadButtonState: Equatable {
    case notDownloaded
    case queued
    case inProgress(Double)      // anneau de progression 0…1
    case paused(Double)
    case completed
    case failed

    /// Mappe un état persistant (ou son absence) vers l'état visuel du bouton.
    static func from(_ ui: DownloadUiState?) -> DownloadButtonState {
        guard let ui else { return .notDownloaded }
        switch ui.status {
        case .queued:      return .queued
        case .downloading: return .inProgress(ui.percent)
        case .removing:    return .inProgress(ui.percent)   // transitoire : spinner
        case .paused:      return .paused(ui.percent)
        case .completed:   return .completed
        case .failed:      return .failed
        }
    }

    /// Label VoiceOver (français), annonce état + % quand pertinent.
    var accessibilityLabel: String {
        switch self {
        case .notDownloaded:       return "Télécharger"
        case .queued:              return "En file d'attente"
        case .inProgress(let p):   return "Téléchargement \(Int((p * 100).rounded())) %"
        case .paused(let p):       return "En pause \(Int((p * 100).rounded())) %"
        case .completed:           return "Disponible hors ligne"
        case .failed:              return "Échec — appuyer pour réessayer"
        }
    }
}
