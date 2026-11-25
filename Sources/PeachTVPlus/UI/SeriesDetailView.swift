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

    func downloadKey(_ ep: Episode) -> String { "episode:\(ep.id)" }

    func enqueueDownload(_ ep: Episode) {
        guard let pid = container.repository.activePlaylist?.id,
              let factory = container.activeFactory else { return }
        let ext = (ep.containerExtension?.isEmpty == false) ? ep.containerExtension!
                                                            : PlaybackURLBuilder.defaultVodExtension
        let masked = factory.maskedStreamURLString(kind: .series, id: ep.id, ext: ext)
        let num = ep.episodeNumber.map { "E\($0)" } ?? ""
        let title = "\(series.name) · S\(ep.seasonNumber)\(num)"
        container.downloadManager.enqueue(contentKey: downloadKey(ep), contentType: .series,
                                          playlistId: pid, title: title, maskedURL: masked, ext: ext)
    }
}

/// Détail d'une série : saisons → épisodes, lecture d'un épisode. Atteint depuis la Recherche
/// et les Favoris. Les infos (résumé, genre, distribution) viennent de `get_series_info` (M1).
struct SeriesDetailView: View {
    @StateObject private var vm: SeriesDetailViewModel
    @State private var presentation: EpisodePresentation?
    private let container: AppContainer

    init(series: Series, container: AppContainer) {
        self.container = container
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
            EpisodePlayerView(episodes: p.episodes, startIndex: p.startIndex,
                              seriesName: vm.series.name, container: container,
                              onClose: { presentation = nil })
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
                        HStack(spacing: 12) {
                            Button {
                                let all = detail.seasons.flatMap(\.episodes)
                                if let i = all.firstIndex(of: episode) {
                                    presentation = EpisodePresentation(episodes: all, startIndex: i)
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Text(episodeLabel(episode))
                                        .font(.subheadline.monospacedDigit())
                                        .foregroundStyle(Theme.accent)
                                        .frame(minWidth: 44, alignment: .leading)
                                    Text(episode.title).lineLimit(1)
                                    Spacer()
                                    Image(systemName: "play.circle").foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            DownloadControl(container: container,
                                            contentKey: vm.downloadKey(episode),
                                            enqueue: { vm.enqueueDownload(episode) },
                                            compact: true)
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
