import SwiftUI

@MainActor
final class MoviesViewModel: ObservableObject {
    @Published var categories: [Category] = []
    @Published var movies: [Movie] = []
    @Published var selectedCategoryId: String?
    @Published var isLoading = false
    /// Cause réelle d'un catalogue vide (voir correctif ①), `nil` si tout va bien.
    @Published var syncError: String?

    private let container: AppContainer
    init(container: AppContainer) { self.container = container }

    func loadInitial() async {
        guard movies.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        var cats = (try? container.catalogStore.categories(type: .vod)) ?? []
        if cats.isEmpty {
            await container.catalogSync.sync()
            syncError = container.catalogSync.lastError
            cats = (try? container.catalogStore.categories(type: .vod)) ?? []
        }
        categories = cats
        if selectedCategoryId == nil { selectedCategoryId = Self.defaultCategory(cats)?.id }
        reload()
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        await container.catalogSync.sync()
        syncError = container.catalogSync.lastError
        categories = (try? container.catalogStore.categories(type: .vod)) ?? []
        reload()
    }

    func select(_ id: String?) { selectedCategoryId = id; reload() }

    private func reload() {
        movies = (try? container.catalogStore.movies(categoryId: selectedCategoryId, limit: 300)) ?? []
    }

    var selectedCategoryName: String {
        guard let id = selectedCategoryId else { return "Tous les films" }
        return categories.first { $0.id == id }?.name ?? "Catégorie"
    }

    /// Catégorie par défaut présélectionnée = « À l'affiche » (nom contenant « affiche »),
    /// sinon la première. Reprise du `defaultCatalogCategory` Android. Partagée avec les Séries.
    static func defaultCategory(_ cats: [Category]) -> Category? {
        cats.first { $0.name.localizedCaseInsensitiveContains("affiche") } ?? cats.first
    }
}

/// Écran **Films** : grille adaptative de pochettes, filtre par catégorie (défaut « À l'affiche »),
/// tap → fiche détail. Lecture via `PlaybackURLBuilder.movie`. Sous-onglet de l'Accueil.
struct MoviesView: View {
    @StateObject private var vm: MoviesViewModel
    private let container: AppContainer

    init(container: AppContainer) {
        self.container = container
        _vm = StateObject(wrappedValue: MoviesViewModel(container: container))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !vm.categories.isEmpty {
                    CategoryChips(categories: vm.categories,
                                  selectedId: vm.selectedCategoryId,
                                  allLabel: "Tous",
                                  onSelect: { vm.select($0) })
                    Divider()
                }
                content
            }
            .navigationTitle("Films")
            .navigationBarTitleDisplayMode(.inline)
            .task { await vm.loadInitial() }
        }
    }

    @ViewBuilder private var content: some View {
        if vm.isLoading && vm.movies.isEmpty {
            ProgressView("Chargement du catalogue…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.movies.isEmpty {
            emptyState
        } else {
            grid
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: PosterGrid.columns, spacing: 14) {
                ForEach(vm.movies) { movie in
                    NavigationLink {
                        MovieDetailView(movie: movie, container: container)
                    } label: {
                        PosterCard(title: movie.name, posterURL: movie.posterURL, rating: movie.rating)
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
            ContentUnavailableView("Aucun film",
                                   systemImage: "film",
                                   description: Text("Tirez pour rafraîchir le catalogue."))
        }
    }

}

// MARK: - Fiche détail film

@MainActor
final class MovieDetailViewModel: ObservableObject {
    @Published private(set) var detail: MovieDetail?
    @Published private(set) var isLoading = false

    let movie: Movie
    private let container: AppContainer

    init(movie: Movie, container: AppContainer) {
        self.movie = movie
        self.container = container
    }

    func load() async {
        guard detail == nil else { return }
        isLoading = true
        defer { isLoading = false }
        detail = await container.repository.movieDetail(for: movie)
    }

    func request() -> PlaybackRequest? {
        container.activeFactory.map { PlaybackURLBuilder.movie(movie, factory: $0) }
    }

    var downloadKey: String { "movie:\(movie.id)" }

    func enqueueDownload() {
        guard let pid = container.repository.activePlaylist?.id,
              let factory = container.activeFactory else { return }
        let ext = (movie.containerExtension?.isEmpty == false) ? movie.containerExtension!
                                                               : PlaybackURLBuilder.defaultVodExtension
        let masked = factory.maskedStreamURLString(kind: .movie, id: movie.id, ext: ext)
        container.downloadManager.enqueue(contentKey: downloadKey, contentType: .vod,
                                          playlistId: pid, title: movie.name, maskedURL: masked, ext: ext)
    }
}

/// Fiche d'un film : affiche, titre, genre/note/date, résumé, bouton Lecture.
/// (Le téléchargement hors-ligne sera câblé au chantier ④.)
struct MovieDetailView: View {
    @StateObject private var vm: MovieDetailViewModel
    @State private var presentation: PlayerPresentation?
    private let container: AppContainer

    init(movie: Movie, container: AppContainer) {
        self.container = container
        _vm = StateObject(wrappedValue: MovieDetailViewModel(movie: movie, container: container))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    PosterThumb(posterURL: vm.detail?.movie.posterURL ?? vm.movie.posterURL)
                        .frame(width: 120, height: 180)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(vm.movie.name).font(.title3.bold())
                        if let genre = vm.detail?.genre, !genre.isEmpty {
                            Text(genre).font(.caption).foregroundStyle(.secondary)
                        }
                        if let rating = vm.detail?.movie.rating ?? vm.movie.rating, rating > 0 {
                            Label(String(format: "%.1f", rating), systemImage: "star.fill")
                                .font(.caption).foregroundStyle(Theme.ratingStar)
                        }
                        if let date = vm.detail?.releaseDate, !date.isEmpty {
                            Text(date).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }

                Button {
                    if let r = vm.request() { presentation = PlayerPresentation(request: r) }
                } label: {
                    Label("Lecture", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)

                DownloadControl(container: container, contentKey: vm.downloadKey) {
                    vm.enqueueDownload()
                }
                .frame(maxWidth: .infinity)

                if let plot = vm.detail?.plot, !plot.isEmpty {
                    Text(plot).font(.callout).foregroundStyle(.secondary)
                }
                if vm.isLoading && vm.detail == nil {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .padding()
        }
        .navigationTitle(vm.movie.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
        .fullScreenCover(item: $presentation) { p in
            PlayerView(request: p.request, onClose: { presentation = nil })
        }
    }
}
