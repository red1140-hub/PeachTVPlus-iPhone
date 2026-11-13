import Foundation

// MARK: - File d'attente (max N parallèles, FIFO)

/// Sélectionne les téléchargements à démarrer sans dépasser le plafond de parallélisme.
/// Pur → testable. Voir `docs/PORT-SPEC.md §6` (max 3 parallèles, FIFO réordonnable).
struct DownloadQueuePolicy: Equatable {
    var maxConcurrent = 3

    /// `contentKey`s en file (`queued`) à lancer maintenant : comble les places libres, FIFO
    /// (ordre d'arrivée = `updatedAt` croissant).
    func nextToStart(records: [DownloadRecord]) -> [String] {
        let downloading = records.filter { $0.downloadStatus == .downloading }.count
        let slots = max(0, maxConcurrent - downloading)
        guard slots > 0 else { return [] }
        return records
            .filter { $0.downloadStatus == .queued }
            .sorted { $0.updatedAt < $1.updatedAt }
            .prefix(slots)
            .map(\.contentKey)
    }
}

// MARK: - Garde-fou d'espace disque

/// Refuse un transfert si l'espace libre ne couvre pas la taille estimée + une marge de
/// sécurité. **Pas** de retry en boucle sur disque plein. Voir `docs/reliability-and-qa.md iDL-05`.
enum DiskSpaceGuard {
    /// Marge gardée libre (ne pas remplir le disque à ras bord).
    static let safetyMarginBytes: Int64 = 300 * 1024 * 1024   // 300 Mo

    /// Décision pure (testable en injectant `freeBytes`).
    static func canStart(estimatedBytes: Int64, freeBytes: Int64) -> Bool {
        guard estimatedBytes >= 0 else { return false }
        return freeBytes - estimatedBytes >= safetyMarginBytes
    }

    /// Espace libre réel pour usage important (best-effort ; `nil` si indéterminable).
    static func systemFreeBytes() -> Int64? {
        let url = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                in: .userDomainMask, appropriateFor: nil, create: false))
            ?? URL(fileURLWithPath: NSHomeDirectory())
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }
}

// MARK: - « Wi-Fi uniquement »

enum NetworkPathType: Equatable { case wifi, cellular, none }

/// Décide si un transfert est autorisé selon le lien courant et le réglage « Wi-Fi uniquement »
/// (défaut ON). Sur cellulaire avec le réglage actif → pause auto ; reprise au retour du Wi-Fi.
struct WiFiOnlyPolicy: Equatable {
    var wifiOnly = true

    func allows(_ path: NetworkPathType) -> Bool {
        switch path {
        case .none:     return false
        case .wifi:     return true
        case .cellular: return !wifiOnly
        }
    }
}

// MARK: - Erreurs de téléchargement (message + politique de retry)

struct DownloadError: Error, Equatable {
    enum Kind: Equatable {
        case subscriptionExpired     // 401/403 pendant transfert
        case insufficientStorage     // disque plein
        case serverUnreachable
        case network                 // coupure réseau (repris plus tard)
        case unknown
    }

    let kind: Kind
    let message: String
    let allowsRetry: Bool

    /// `isDiskFull` prioritaire, puis code HTTP, puis erreur réseau. Voir
    /// `docs/reliability-and-qa.md §2` (lignes DL).
    static func classify(statusCode: Int? = nil, isDiskFull: Bool = false,
                         urlErrorCode: URLError.Code? = nil) -> DownloadError {
        if isDiskFull {
            return DownloadError(kind: .insufficientStorage,
                                 message: "Stockage insuffisant pour télécharger.", allowsRetry: false)
        }
        if statusCode == 401 || statusCode == 403 {
            return DownloadError(kind: .subscriptionExpired,
                                 message: "Téléchargement arrêté : abonnement expiré.", allowsRetry: false)
        }
        switch urlErrorCode {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            return DownloadError(kind: .network,
                                 message: "Téléchargement en pause : pas de connexion.", allowsRetry: true)
        case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .timedOut:
            return DownloadError(kind: .serverUnreachable,
                                 message: "Serveur injoignable, téléchargement en pause.", allowsRetry: true)
        case .some:
            return DownloadError(kind: .unknown,
                                 message: "Téléchargement interrompu.", allowsRetry: true)
        case nil:
            return DownloadError(kind: .unknown,
                                 message: "Téléchargement interrompu.", allowsRetry: true)
        }
    }
}
