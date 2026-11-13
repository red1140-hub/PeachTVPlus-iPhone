import Foundation

/// Coffre d'identifiants **thread-safe** : le délégué `URLSession` background du
/// `DownloadManager` tourne hors du main actor et a besoin des identifiants pour réinjecter
/// `__cred__`. On ne peut donc pas lui faire lire `XtreamRepository` (@MainActor) directement.
/// `AppContainer` tient ce coffre à jour à chaque changement de listes.
final class CredentialsVault: @unchecked Sendable {
    private var map: [String: XtreamCredentials] = [:]
    private let lock = NSLock()

    func set(_ playlists: [Playlist]) {
        lock.lock(); defer { lock.unlock() }
        map = Dictionary(playlists.map { ($0.id, $0.credentials) }, uniquingKeysWith: { a, _ in a })
    }

    func credentials(for playlistId: String) -> XtreamCredentials? {
        lock.lock(); defer { lock.unlock() }
        return map[playlistId]
    }
}

/// Racine d'injection de dépendances (M5). Construit **un seul** writer GRDB partagé par le
/// catalogue et les téléchargements, le repository (câblé au cache), le gestionnaire de
/// téléchargements (avec le coffre d'identifiants), le consentement HTTP et le service de
/// synchronisation du catalogue. Centralise aussi le **retrait d'une liste** (purge ses
/// téléchargements + délègue au repository pour catalogue/Keychain). Voir `docs/PORT-SPEC.md §8`.
@MainActor
final class AppContainer: ObservableObject {

    /// Référence accessible à l'`AppDelegate` pour `handleEventsForBackgroundURLSession`.
    static private(set) var shared: AppContainer?

    let catalogStore: CatalogStore
    let downloadStore: DownloadStore
    let repository: XtreamRepository
    let consent: CleartextConsent
    let downloadManager: DownloadManager
    let catalogSync: CatalogSyncService

    private let vault = CredentialsVault()

    init(catalog: CatalogStore, downloads: DownloadStore, consent: CleartextConsent = CleartextConsent()) {
        self.catalogStore = catalog
        self.downloadStore = downloads
        self.consent = consent
        self.repository = XtreamRepository(catalog: catalog)
        self.catalogSync = CatalogSyncService(repository: repository, catalog: catalog)

        let vault = self.vault
        self.downloadManager = DownloadManager(store: downloads) { playlistId in
            vault.credentials(for: playlistId)
        }

        refreshVault()
        AppContainer.shared = self
    }

    /// Conteneur de production (base sur disque ; repli mémoire si la base est indisponible).
    static func live() -> AppContainer {
        if let stores = try? AppDatabase.sharedOnDisk() {
            return AppContainer(catalog: stores.catalog, downloads: stores.downloads)
        }
        RedactingLogger.error("Base de cache indisponible — repli en mémoire")
        let stores = try! AppDatabase.sharedInMemory()
        return AppContainer(catalog: stores.catalog, downloads: stores.downloads)
    }

    /// Fabrique d'URLs de flux pour la liste active (identifiants réels).
    var activeFactory: XtreamURLFactory? {
        repository.activeCredentials.map(XtreamURLFactory.init)
    }

    /// Au lancement : se rattacher aux téléchargements background survivants.
    func start() { downloadManager.restore() }

    /// Doit être appelé après toute mutation des listes (login, bascule, retrait).
    func refreshVault() { vault.set(repository.playlists) }

    /// Retrait d'une liste : annule + supprime ses téléchargements (fichiers compris), puis
    /// délègue au repository (qui purge le cache catalogue + le Keychain ; dernière liste →
    /// tout effacé, loi 25).
    func removePlaylist(_ id: String) {
        let keys = ((try? downloadStore.all()) ?? [])
            .filter { $0.playlistId == id }
            .map(\.contentKey)
        for key in keys { downloadManager.remove(key) }
        try? downloadStore.purgePlaylist(id)

        repository.removePlaylist(id)
        if repository.playlists.isEmpty { try? downloadStore.clearAll() }
        refreshVault()
    }
}
