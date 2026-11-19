import SwiftUI

@MainActor
final class SeriesListViewModel: ObservableObject {
    @Published var categories: [Category] = []
    @Published var series: [Series] = []
    @Published var selectedCategoryId: String? = SeriesListViewModel.allId   // défaut = « Toutes »
    @Published var isLoading = false
    @Published var syncError: String?

    static let allId = "__all__"
    static let favId = "__fav__"

    private let container: AppContainer
    private var hasLoaded = false
    init(container: AppContainer) { self.container = container }

    private var playlistId: String? { container.repository.activePlaylist?.id }

    func loadInitial() async {
        guard !hasLoaded else { return }
        isLoading = true
        defer { isLoading = false }
        var cats = (try? container.catalogStore.categories(type: .series)) ?? []
        if cats.isEmpty {
            await container.catalogSync.sync()
            syncError = container.catalogSync.lastError
            cats = (try? container.catalogStore.categories(type: .series)) ?? []
        }
        categories = cats
        reload()
        if !cats.isEmpty { hasLoaded = true }
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        await container.catalogSync.sync()
        syncError = container.catalogSync.lastError
        categories = (try? container.catalogStore.categories(type: .series)) ?? []
        reload()
    }

    func select(_ id: String?) { selectedCategoryId = id; reload() }
    func reloadState() { reload() }

    private func reload() {
        switch selectedCategoryId {
        case Self.favId:
            series = favoriteSeries()
        case nil, Self.allId:
            series = (try? container.catalogStore.series(categoryId: nil, limit: 500)) ?? []
        default:
            series = (try? container.catalogStore.series(categoryId: selectedCategoryId, limit: 500)) ?? []
        }
    }

    private func favoriteSeries() -> [Series] {
        guard let pid = playlistId else { return [] }
        let favs = (try? container.catalogStore.favorites(playlistId: pid, contentType: .series)) ?? []
        return favs.map { Series(id: $0.itemId, name: $0.name ?? $0.itemId, posterURL: $0.posterURL,
                                 categoryId: nil, rating: nil) }
    }

    /// Menu : « Favoris » (#1), « Toutes », puis les catégories réelles.
    var menuCategories: [Category] {
        var out: [Category] = [
            Category(id: Self.favId, name: "★ Favoris", contentType: .series),
            Category(id: Self.allId, name: "Toutes", contentType: .series)
        ]
        out.append(contentsOf: categories)
        return out
    }

    var selectedCategoryName: String {
        switch selectedCategoryId {
        case Self.favId:      return "★ Favoris"
        case nil, Self.allId: return "Toutes"
        default:              return categories.first { $0.id == selectedCategoryId }?.name ?? "Catégorie"
        }
    }
}

/// Écran **Séries** : grille adaptative de pochettes, filtre par catégorie (défaut « À l'affiche »),
/// tap → `SeriesDetailView` (saisons/épisodes, déjà existant). Sous-onglet de l'Accueil.
struct SeriesListView: View {
    @StateObject private var vm: SeriesListViewModel
    private let container: AppContainer

    init(container: AppContainer) {
        self.container = container
        _vm = StateObject(wrappedValue: SeriesListViewModel(container: container))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !vm.categories.isEmpty {
                    CategoryDropdown(selectedName: vm.selectedCategoryName,
                                     entries: vm.menuCategories,
                                     selectedId: vm.selectedCategoryId,
                                     onSelect: { vm.select($0) })
                    Divider()
                }
                content
            }
            .toolbar(.hidden, for: .navigationBar)
            .task { await vm.loadInitial() }
            .onAppear { vm.reloadState() }
        }
    }

    @ViewBuilder private var content: some View {
        if vm.isLoading && vm.series.isEmpty {
            ProgressView("Chargement du catalogue…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.series.isEmpty {
            emptyState
        } else {
            grid
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: PosterGrid.columns, spacing: 14) {
                ForEach(vm.series) { show in
                    NavigationLink {
                        SeriesDetailView(series: show, container: container)
                    } label: {
                        PosterCard(title: show.name, posterURL: show.posterURL, rating: show.rating)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
        }
        .refreshable { await vm.refresh() }
    }

    @ViewBuilder private var emptyState: some View {
        if let error = vm.syncError {
            ContentUnavailableView {
                Label("Catalogue indisponible", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Réessayer") { Task { await vm.refresh() } }
            }
        } else {
            ContentUnavailableView("Aucune série",
                                   systemImage: "tv",
                                   description: Text("Tirez pour rafraîchir le catalogue."))
        }
    }

}
