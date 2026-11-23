import SwiftUI

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query = ""
    @Published private(set) var liveResults: [LiveChannel] = []
    @Published private(set) var movieResults: [Movie] = []
    @Published private(set) var seriesResults: [Series] = []
    /// 5 dernières recherches (plus récente d'abord), persistées entre les sessions.
    @Published private(set) var recents: [String] = []

    private let container: AppContainer
    private let recentsKey = "search.recent"
    private let maxRecents = 5

    init(container: AppContainer) {
        self.container = container
        recents = (UserDefaults.standard.array(forKey: recentsKey) as? [String]) ?? []
    }

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

    /// Mémorise la recherche courante (à la soumission ou quand un résultat est ouvert).
    func commitRecent() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return }
        recents.removeAll { $0.caseInsensitiveCompare(q) == .orderedSame }
        recents.insert(q, at: 0)
        if recents.count > maxRecents { recents = Array(recents.prefix(maxRecents)) }
        persist()
    }

    func apply(_ term: String) { query = term; search() }
    func removeRecent(_ term: String) { recents.removeAll { $0 == term }; persist() }
    func clearRecents() { recents = []; persist() }

    private func persist() { UserDefaults.standard.set(recents, forKey: recentsKey) }

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
    @FocusState private var searchFocused: Bool
    private let container: AppContainer

    init(container: AppContainer) {
        self.container = container
        _vm = StateObject(wrappedValue: SearchViewModel(container: container))
    }

    private var queryIsShort: Bool {
        vm.query.trimmingCharacters(in: .whitespaces).count < 2
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                Divider()
                content
            }
            .navigationTitle("Recherche")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                // Focus + clavier dès l'arrivée sur l'onglet (comportement Android).
                DispatchQueue.main.async { searchFocused = true }
            }
            .onChange(of: vm.query) { _, _ in vm.search() }
            .fullScreenCover(item: $presentation) { p in
                PlayerView(request: p.request, onClose: { presentation = nil })
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Titre", text: $vm.query)
                .focused($searchFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .onSubmit { vm.commitRecent() }
            if !vm.query.isEmpty {
                Button {
                    vm.query = ""
                    searchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Effacer la recherche")
            }
        }
        .padding(10)
        .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder private var content: some View {
        if queryIsShort {
            if vm.recents.isEmpty {
                ContentUnavailableView("Rechercher",
                                       systemImage: "magnifyingglass",
                                       description: Text("Chaînes, films et séries par titre."))
            } else {
                recentsList
            }
        } else if !vm.hasResults {
            ContentUnavailableView.search(text: vm.query)
        } else {
            resultsList
        }
    }

    private var recentsList: some View {
        List {
            Section("Recherches récentes") {
                ForEach(vm.recents, id: \.self) { term in
                    Button {
                        searchFocused = false
                        vm.apply(term)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary)
                            Text(term).foregroundStyle(.primary)
                            Spacer()
                        }
                    }
                    .swipeActions {
                        Button("Retirer", role: .destructive) { vm.removeRecent(term) }
                    }
                }
            }
            Section {
                Button("Effacer l'historique", role: .destructive) { vm.clearRecents() }
            }
        }
        .listStyle(.plain)
    }

    private var resultsList: some View {
        List {
            if !vm.liveResults.isEmpty {
                Section("Direct") {
                    ForEach(vm.liveResults) { channel in
                        Button(channel.name) {
                            vm.commitRecent()
                            if let r = vm.liveRequest(channel) { presentation = PlayerPresentation(request: r) }
                        }
                    }
                }
            }
            if !vm.movieResults.isEmpty {
                Section("Films") {
                    ForEach(vm.movieResults) { movie in
                        Button(movie.name) {
                            vm.commitRecent()
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
                        .simultaneousGesture(TapGesture().onEnded { vm.commitRecent() })
                    }
                }
            }
        }
    }
}
