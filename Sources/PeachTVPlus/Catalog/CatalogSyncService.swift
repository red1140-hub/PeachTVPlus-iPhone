import Foundation

/// Synchronise le catalogue distant (API Xtream) vers le cache GRDB local (catégories, chaînes
/// Live, films, séries). Le reste de l'UI lit **toujours** le cache (listes paginées + recherche
/// FTS5), jamais l'API directement — c'est le modèle Android (source de vérité locale).
///
/// Anti-données-fantômes : on capture `playlistEpoch` avant les fetchs et on **abandonne**
/// l'écriture si la liste active a changé entre-temps. Voir `docs/PORT-SPEC.md §4`.
@MainActor
final class CatalogSyncService: ObservableObject {

    private let repository: XtreamRepository
    private let catalog: CatalogStore

    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncedAt: Date?
    /// Message FR de la dernière synchro ratée (prêt à afficher, aucun secret) ; `nil` si la
    /// dernière a réussi. L'UI s'en sert pour montrer la **vraie cause** au lieu d'un vide muet.
    @Published private(set) var lastError: String?

    init(repository: XtreamRepository, catalog: CatalogStore) {
        self.repository = repository
        self.catalog = catalog
    }

    /// Recharge le cache depuis le serveur actif. Sans effet si déjà en cours ou non connecté.
    func sync() async {
        guard !isSyncing, repository.isLoggedIn else { return }
        isSyncing = true
        defer { isSyncing = false }

        let epoch = repository.playlistEpoch

        do {
            // Appels séquentiels (repository est @MainActor ; on reste sur le main actor).
            // Toute erreur réseau/HTTP/décodage **remonte ici** au lieu de devenir une liste
            // vide : sans ça, l'UI affichait « Aucune chaîne » sans jamais montrer la cause.
            let liveCats = try await repository.liveCategories()
            let vodCats = try await repository.vodCategories()
            let seriesCats = try await repository.seriesCategories()
            let channels = try await repository.liveChannels(categoryId: nil)
            let films = try await repository.movies(categoryId: nil)
            let shows = try await repository.seriesList(categoryId: nil)

            // La source a changé pendant les fetchs → ces données sont périmées, on jette.
            guard epoch == repository.playlistEpoch else { return }

            // On n'écrit le cache **que sur succès complet** : on n'écrase jamais un cache
            // utile par des listes vides issues d'une panne.
            try catalog.saveCategories(liveCats + vodCats + seriesCats)
            try catalog.saveLiveChannels(channels)
            try catalog.saveMovies(films)
            try catalog.saveSeries(shows)
            lastSyncedAt = Date()
            lastError = nil
        } catch {
            lastError = Self.describe(error)
            RedactingLogger.error("Synchronisation du catalogue échouée — \(error)")
        }
    }

    /// Traduit une erreur en message FR court et sûr (aucun secret).
    private static func describe(_ error: Error) -> String {
        if let api = error as? APIError { return api.frenchMessage }
        return "Échec d'enregistrement du catalogue en local."
    }
}
