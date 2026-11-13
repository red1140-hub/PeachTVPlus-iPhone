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

        // Appels séquentiels (repository est @MainActor ; on reste sur le main actor).
        let liveCats = await repository.liveCategories()
        let vodCats = await repository.vodCategories()
        let seriesCats = await repository.seriesCategories()
        let channels = await repository.liveChannels(categoryId: nil)
        let films = await repository.movies(categoryId: nil)
        let shows = await repository.seriesList(categoryId: nil)

        // La source a changé pendant les fetchs → ces données sont périmées, on jette.
        guard epoch == repository.playlistEpoch else { return }

        do {
            try catalog.saveCategories(liveCats + vodCats + seriesCats)
            try catalog.saveLiveChannels(channels)
            try catalog.saveMovies(films)
            try catalog.saveSeries(shows)
            lastSyncedAt = Date()
        } catch {
            RedactingLogger.error("Synchronisation du catalogue échouée — \(error)")
        }
    }
}
