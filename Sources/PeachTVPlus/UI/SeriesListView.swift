import SwiftUI

@MainActor
final class SeriesListViewModel: ObservableObject {
    @Published var categories: [Category] = []
    @Published var series: [Series] = []
    @Published var selectedCategoryId: String?
    @Published var isLoading = false
    @Published var syncError: String?

    private let container: AppContainer
    init(container: AppContainer) { self.container = container }

    func loadInitial() async {
        guard series.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        var cats = (try? container.catalogStore.categories(type: .series)) ?? []
        if cats.isEmpty {
            await container.catalogSync.sync()
            syncError = container.catalogSync.lastError
            cats = (try? container.catalogStore.categories(type: .series)) ?? []
        }
        categories = cats
        if selectedCategoryId == nil { selectedCategoryId = MoviesViewModel.defaultCategory(cats)?.id }
        reload()
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

    private func reload() {
        series = (try? container.catalogStore.series(categoryId: selectedCategoryId, limit: 300)) ?? []
    }

    var selectedCategoryName: String {
        guard let id = selectedCategoryId else { return "Toutes les séries" }
        return categories.first { $0.id == id }?.name ?? "Catégorie"
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
            Group {
                if vm.isLoading && vm.series.isEmpty {
                    ProgressView("Chargement du catalogue…")
                } else if vm.series.isEmpty {
                    emptyState
                } else {
                    grid
                }
            }
            .navigationTitle("Séries")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { categoryMenu }
            .task { await vm.loadInitial() }
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

    private var categoryMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Toutes les séries") { vm.select(nil) }
                Divider()
                ForEach(vm.categories) { cat in Button(cat.name) { vm.select(cat.id) } }
            } label: {
                Label(vm.selectedCategoryName, systemImage: "line.3.horizontal.decrease.circle")
            }
        }
    }
}
