import SwiftUI

/// Boutons « épisode précédent / suivant » affichés par `PlayerView` (barre du haut, VOD).
struct EpisodeControls {
    let hasPrevious: Bool
    let hasNext: Bool
    let previous: () -> Void
    let next: () -> Void
}

/// Présentation `.fullScreenCover(item:)` du lecteur d'épisodes.
struct EpisodePresentation: Identifiable {
    let id = UUID()
    let episodes: [Episode]
    let startIndex: Int
}

/// Libellé avec l'icône **après** le texte (« Suiv. › »).
struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon
        }
    }
}

/// Enveloppe du lecteur **Épisodes** (sur le modèle de `LivePlayerView`) : tient l'index de
/// l'épisode courant dans la liste aplatie saisons → épisodes, enchaîne automatiquement sur le
/// suivant à la fin de la lecture, et propose « Préc. / Suiv. » à l'écran (pas de glissé).
struct EpisodePlayerView: View {
    let episodes: [Episode]
    let seriesName: String
    let container: AppContainer
    var onClose: () -> Void

    @State private var index: Int

    init(episodes: [Episode], startIndex: Int, seriesName: String,
         container: AppContainer, onClose: @escaping () -> Void) {
        self.episodes = episodes
        self.seriesName = seriesName
        self.container = container
        self.onClose = onClose
        _index = State(initialValue: startIndex)
    }

    private var current: Episode? {
        episodes.indices.contains(index) ? episodes[index] : nil
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let current, let request = episodeRequest(current) {
                PlayerView(
                    request: request,
                    onClose: onClose,
                    onEnded: goToNextOrClose,
                    episodeControls: EpisodeControls(
                        hasPrevious: index > 0,
                        hasNext: index < episodes.count - 1,
                        previous: { step(-1) },
                        next: { step(1) }
                    ),
                    resumeAt: savedPosition(for: current),
                    onProgress: { pos, dur in saveProgress(episode: current, position: pos, duration: dur) }
                )
                .id(current.id)                       // relance le lecteur sur le nouvel épisode
            } else {
                Button("Fermer", action: onClose).tint(.white)
            }
        }
    }

    private func episodeRequest(_ e: Episode) -> PlaybackRequest? {
        container.activeFactory.map {
            PlaybackURLBuilder.episode(e, seriesName: seriesName, factory: $0)
        }
    }

    // MARK: Reprise de lecture

    private func positionKey(_ e: Episode) -> String { "episode:\(e.id)" }

    /// Lue à la construction du lecteur (recréé par `.id(current.id)` à chaque épisode).
    private func savedPosition(for e: Episode) -> Double? {
        guard let rec = try? container.catalogStore.position(contentKey: positionKey(e)) else { return nil }
        return Double(rec.positionSeconds)
    }

    private func saveProgress(episode e: Episode, position: Int, duration: Int?) {
        var label = e.title
        if let n = e.episodeNumber { label = "S\(e.seasonNumber)E\(n) · \(e.title)" }
        let rec = PlaybackPositionRecord(
            contentKey: positionKey(e),
            contentType: ContentType.series.rawValue,
            positionSeconds: position,
            durationSeconds: duration,
            title: "\(seriesName) — \(label)",
            posterURL: e.posterURL,
            updatedAt: Date().timeIntervalSince1970)
        try? container.catalogStore.savePosition(rec)
    }

    private func step(_ delta: Int) {
        let target = index + delta
        guard episodes.indices.contains(target) else { return }
        index = target
    }

    /// Fin d'épisode : on enchaîne ; au dernier épisode on ferme le lecteur.
    private func goToNextOrClose() {
        if index < episodes.count - 1 { index += 1 } else { onClose() }
    }
}
