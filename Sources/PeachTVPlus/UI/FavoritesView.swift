import SwiftUI

@MainActor
final class FavoritesViewModel: ObservableObject {
    @Published private(set) var liveFavorites: [FavoriteRecord] = []
    @Published private(set) var movieFavorites: [FavoriteRecord] = []
    @Published private(set) var seriesFavorites: [FavoriteRecord] = []

    private let container: AppContainer
    init(container: AppContainer) { self.container = container }

    func reload() {
        guard let pid = container.repository.activePlaylist?.id else {
            liveFavorites = []; movieFavorites = []; seriesFavorites = []
            return
        }
        liveFavorites = (try? container.catalogStore.favorites(playlistId: pid, contentType: .live)) ?? []
        movieFavorites = (try? container.catalogStore.favorites(playlistId: pid, contentType: .vod)) ?? []
        seriesFavorites = (try? container.catalogStore.favorites(playlistId: pid, contentType: .series)) ?? []
    }

    func remove(contentType: ContentType, itemId: String) {
        guard let pid = container.repository.activePlaylist?.id else { return }
        try? container.catalogStore.removeFavorite(playlistId: pid, contentType: contentType, itemId: itemId)
        reload()
    }

    func liveRequest(_ record: FavoriteRecord) -> PlaybackRequest? {
        container.activeFactory.map {
            PlaybackRequest(url: $0.liveStreamURL(id: record.itemId),
                            title: record.name ?? record.itemId, isLive: true)
        }
    }

    func movieRequest(_ record: FavoriteRecord) -> PlaybackRequest? {
        container.activeFactory.map {
            PlaybackRequest(url: $0.movieURL(id: record.itemId, ext: PlaybackURLBuilder.defaultVodExtension),
                            title: record.name ?? record.itemId, isLive: false)
        }
    }

    var isEmpty: Bool { liveFavorites.isEmpty && movieFavorites.isEmpty && seriesFavorites.isEmpty }
}

struct FavoritesView: View {
    @StateObject private var vm: FavoritesViewModel
    @State private var presentation: PlayerPresentation?
    private let container: AppContainer

    init(container: AppContainer) {
        self.container = container
        _vm = StateObject(wrappedValue: FavoritesViewModel(container: container))
    }

    var body: some View {
        NavigationStack {
            Group {
                if vm.isEmpty {
                    ContentUnavailableView("Aucun favori",
                                           systemImage: "star",
                                           description: Text("Ajoutez des chaînes et des films à vos favoris pour les retrouver ici."))
                } else {
                    list
                }
            }
            .navigationTitle("Favoris")
            .onAppear { vm.reload() }
            .fullScreenCover(item: $presentation) { p in
                PlayerView(request: p.request, onClose: { presentation = nil })
            }
        }
    }

    /// Série minimale reconstituée depuis un favori (seul `id` est requis pour charger le détail).
    private static func series(from fav: FavoriteRecord) -> Series {
        Series(id: fav.itemId, name: fav.name ?? fav.itemId,
               posterURL: fav.posterURL, categoryId: nil, rating: nil)
    }

    private var list: some View {
        List {
            if !vm.liveFavorites.isEmpty {
                Section("Direct") {
                    ForEach(vm.liveFavorites, id: \.itemId) { fav in
                        Button(fav.name ?? fav.itemId) {
                            if let r = vm.liveRequest(fav) { presentation = PlayerPresentation(request: r) }
                        }
                        .swipeActions {
                            Button("Retirer", role: .destructive) {
                                vm.remove(contentType: .live, itemId: fav.itemId)
                            }
                        }
                    }
                }
            }
            if !vm.movieFavorites.isEmpty {
                Section("Films") {
                    ForEach(vm.movieFavorites, id: \.itemId) { fav in
                        Button(fav.name ?? fav.itemId) {
                            if let r = vm.movieRequest(fav) { presentation = PlayerPresentation(request: r) }
                        }
                        .swipeActions {
                            Button("Retirer", role: .destructive) {
                                vm.remove(contentType: .vod, itemId: fav.itemId)
                            }
                        }
                    }
                }
            }
            if !vm.seriesFavorites.isEmpty {
                Section("Séries") {
                    ForEach(vm.seriesFavorites, id: \.itemId) { fav in
                        NavigationLink {
                            SeriesDetailView(series: Self.series(from: fav), container: container)
                        } label: {
                            Text(fav.name ?? fav.itemId)
                        }
                        .swipeActions {
                            Button("Retirer", role: .destructive) {
                                vm.remove(contentType: .series, itemId: fav.itemId)
                            }
                        }
                    }
                }
            }
        }
    }
}
