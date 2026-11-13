import SwiftUI

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query = ""
    @Published private(set) var liveResults: [LiveChannel] = []
    @Published private(set) var movieResults: [Movie] = []
    @Published private(set) var seriesResults: [Series] = []

    private let container: AppContainer
    init(container: AppContainer) { self.container = container }

    func search() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { clear(); return }
        // Recherche FTS5 sur le cache (jamais un filtre mémoire).
        liveResults = (try? container.catalogStore.searchLiveChannels(q)) ?? []
        movieResults = (try? container.catalogStore.searchMovies(q)) ?? []
        seriesResults = (try? container.catalogStore.searchSeries(q)) ?? []
    }

    func clear() {
        liveResults = []; movieResults = []; seriesResults = []
    }

    var hasResults: Bool { !liveResults.isEmpty || !movieResults.isEmpty || !seriesResults.isEmpty }

    func liveRequest(_ channel: LiveChannel) -> PlaybackRequest? {
        container.activeFactory.map { PlaybackURLBuilder.live(channel, factory: $0) }
    }
    func movieRequest(_ movie: Movie) -> PlaybackRequest? {
        container.activeFactory.map { PlaybackURLBuilder.movie(movie, factory: $0) }
    }
}

struct SearchView: View {
    @StateObject private var vm: SearchViewModel
    @State private var presentation: PlayerPresentation?
    private let container: AppContainer

    init(container: AppContainer) {
        self.container = container
        _vm = StateObject(wrappedValue: SearchViewModel(container: container))
    }

    var body: some View {
        NavigationStack {
            Group {
                if vm.query.trimmingCharacters(in: .whitespaces).count < 2 {
                    ContentUnavailableView("Rechercher",
                                           systemImage: "magnifyingglass",
                                           description: Text("Chaînes, films et séries par titre."))
                } else if !vm.hasResults {
                    ContentUnavailableView.search(text: vm.query)
                } else {
                    resultsList
                }
            }
            .navigationTitle("Recherche")
            .searchable(text: $vm.query, prompt: "Titre")
            .onChange(of: vm.query) { _, _ in vm.search() }
            .fullScreenCover(item: $presentation) { p in
                PlayerView(request: p.request, onClose: { presentation = nil })
            }
        }
    }

    private var resultsList: some View {
        List {
            if !vm.liveResults.isEmpty {
                Section("Direct") {
                    ForEach(vm.liveResults) { channel in
                        Button(channel.name) {
                            if let r = vm.liveRequest(channel) { presentation = PlayerPresentation(request: r) }
                        }
                    }
                }
            }
            if !vm.movieResults.isEmpty {
                Section("Films") {
                    ForEach(vm.movieResults) { movie in
                        Button(movie.name) {
                            if let r = vm.movieRequest(movie) { presentation = PlayerPresentation(request: r) }
                        }
                    }
                }
            }
            if !vm.seriesResults.isEmpty {
                Section("Séries") {
                    ForEach(vm.seriesResults) { series in
                        NavigationLink {
                            SeriesDetailView(series: series, container: container)
                        } label: {
                            Text(series.name)
                        }
                    }
                }
            }
        }
    }
}
