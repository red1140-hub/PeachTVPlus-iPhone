import Foundation

/// Transforme un élément du catalogue en `PlaybackRequest` (URL de flux réelle + titre + Live).
/// Logique pure et testable ; l'extension de conteneur par défaut est tolérante (films/épisodes
/// Xtream n'exposent pas toujours leur extension). Voir `docs/PORT-SPEC.md §7`.
enum PlaybackURLBuilder {

    static let defaultVodExtension = "mp4"

    static func live(_ channel: LiveChannel, factory: XtreamURLFactory) -> PlaybackRequest {
        PlaybackRequest(url: factory.liveStreamURL(id: channel.id),
                        title: channel.name,
                        isLive: true)
    }

    static func movie(_ movie: Movie, factory: XtreamURLFactory) -> PlaybackRequest {
        let ext = (movie.containerExtension?.isEmpty == false) ? movie.containerExtension! : defaultVodExtension
        return PlaybackRequest(url: factory.movieURL(id: movie.id, ext: ext),
                               title: movie.name,
                               isLive: false)
    }

    static func episode(_ episode: Episode, seriesName: String, factory: XtreamURLFactory) -> PlaybackRequest {
        let ext = (episode.containerExtension?.isEmpty == false) ? episode.containerExtension! : defaultVodExtension
        let label = "S\(episode.seasonNumber)" + (episode.episodeNumber.map { "E\($0)" } ?? "")
        return PlaybackRequest(url: factory.seriesEpisodeURL(episodeId: episode.id, ext: ext),
                               title: seriesName,
                               isLive: false,
                               subtitle: "\(label) · \(episode.title)")
    }
}

/// Enveloppe `Identifiable` pour présenter le lecteur via `.fullScreenCover(item:)`.
struct PlayerPresentation: Identifiable {
    let id = UUID()
    let request: PlaybackRequest
}
