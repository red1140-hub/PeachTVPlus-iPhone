import SwiftUI

@MainActor
final class SeriesDetailViewModel: ObservableObject {
    @Published private(set) var detail: SeriesDetail?
    @Published private(set) var isLoading = false

    let series: Series
    private let container: AppContainer

    init(series: Series, container: AppContainer) {
        self.series = series
        self.container = container
    }

    func load() async {
        guard detail == nil else { return }
        isLoading = true
        defer { isLoading = false }
        detail = await container.repository.seriesDetail(for: series)
    }

    func request(for episode: Episode) -> PlaybackRequest? {
        container.activeFactory.map {
            PlaybackURLBuilder.episode(episode, seriesName: series.name, factory: $0)
        }
    }
}

/// Détail d'une série : saisons → épisodes, lecture d'un épisode. Atteint depuis la Recherche
/// et les Favoris. Les infos (résumé, genre, distribution) viennent de `get_series_info` (M1).
struct SeriesDetailView: View {
    @StateObject private var vm: SeriesDetailViewModel
    @State private var presentation: PlayerPresentation?

    init(series: Series, container: AppContainer) {
        _vm = StateObject(wrappedValue: SeriesDetailViewModel(series: series, container: container))
    }

    var body: some View {
        Group {
            if vm.isLoading && vm.detail == nil {
                ProgressView("Chargement…")
            } else if let detail = vm.detail, !detail.seasons.isEmpty {
                seasonsList(detail)
            } else {
                ContentUnavailableView("Aucun épisode",
                                       systemImage: "rectangle.stack.badge.play",
                                       description: Text("Impossible de charger les épisodes de cette série."))
            }
        }
        .navigationTitle(vm.series.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
        .fullScreenCover(item: $presentation) { p in
            PlayerView(request: p.request, onClose: { presentation = nil })
        }
    }

    private func seasonsList(_ detail: SeriesDetail) -> some View {
        List {
            if let plot = detail.plot, !plot.isEmpty {
                Section {
                    Text(plot).font(.callout).foregroundStyle(.secondary)
                    if let genre = detail.genre, !genre.isEmpty {
                        Text(genre).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            ForEach(detail.seasons) { season in
                Section("Saison \(season.number)") {
                    ForEach(season.episodes) { episode in
                        Button {
                            if let r = vm.request(for: episode) {
                                presentation = PlayerPresentation(request: r)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Text(episodeLabel(episode))
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.orange)
                                    .frame(minWidth: 44, alignment: .leading)
                                Text(episode.title).lineLimit(1)
                                Spacer()
                                Image(systemName: "play.circle").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private func episodeLabel(_ episode: Episode) -> String {
        if let n = episode.episodeNumber { return "É\(n)" }
        return "É"
    }
}
