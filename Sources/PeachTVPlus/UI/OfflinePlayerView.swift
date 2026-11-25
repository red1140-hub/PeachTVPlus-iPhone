import SwiftUI

/// Présentation `.fullScreenCover(item:)` du lecteur **hors-ligne** : la liste des
/// téléchargements **terminés** d'une même section (Films ou Séries) + l'index de départ.
struct OfflinePresentation: Identifiable {
    let id = UUID()
    let items: [DownloadRecord]
    let startIndex: Int
}

/// Enveloppe du lecteur **hors-ligne** (sur le modèle d'`EpisodePlayerView`) : lit le fichier
/// local d'un téléchargement terminé, **reprend** à la position sauvegardée (même `contentKey`
/// que la lecture en ligne → reprise partagée en ligne ↔ hors-ligne), **sauvegarde** la
/// progression, enchaîne automatiquement sur le titre suivant en fin de lecture, et propose
/// « Préc. / Suiv. » pour naviguer entre les titres téléchargés de la section (pas de glissé,
/// comme l'enchaînement des épisodes).
struct OfflinePlayerView: View {
    let items: [DownloadRecord]
    let container: AppContainer
    var onClose: () -> Void

    @State private var index: Int

    init(items: [DownloadRecord], startIndex: Int,
         container: AppContainer, onClose: @escaping () -> Void) {
        self.items = items
        self.container = container
        self.onClose = onClose
        _index = State(initialValue: startIndex)
    }

    private var current: DownloadRecord? {
        items.indices.contains(index) ? items[index] : nil
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let current, let request = offlineRequest(current) {
                PlayerView(
                    request: request,
                    onClose: onClose,
                    onEnded: goToNextOrClose,
                    episodeControls: EpisodeControls(
                        hasPrevious: index > 0,
                        hasNext: index < items.count - 1,
                        previous: { step(-1) },
                        next: { step(1) }
                    ),
                    resumeAt: savedPosition(for: current),
                    onProgress: { pos, dur in saveProgress(record: current, position: pos, duration: dur) }
                )
                .id(current.contentKey)               // relance le lecteur sur le nouveau titre
            } else {
                Button("Fermer", action: onClose).tint(.white)
            }
        }
    }

    /// Lecture **hors-ligne** depuis le fichier local (téléchargement terminé). Jamais de réseau.
    private func offlineRequest(_ rec: DownloadRecord) -> PlaybackRequest? {
        guard rec.downloadStatus == .completed, let path = rec.localPath else { return nil }
        return PlaybackRequest(url: URL(fileURLWithPath: path), title: rec.title, isLive: false)
    }

    // MARK: Reprise de lecture (partagée avec la lecture en ligne via le même contentKey)

    /// Lue à la construction du lecteur (recréé par `.id(contentKey)` à chaque titre).
    private func savedPosition(for rec: DownloadRecord) -> Double? {
        guard let pos = try? container.catalogStore.position(contentKey: rec.contentKey) else { return nil }
        return Double(pos.positionSeconds)
    }

    private func saveProgress(record rec: DownloadRecord, position: Int, duration: Int?) {
        // Préserve l'affiche déjà enregistrée en ligne (le DownloadRecord n'en a pas).
        let existing = try? container.catalogStore.position(contentKey: rec.contentKey)
        let pos = PlaybackPositionRecord(
            contentKey: rec.contentKey,
            contentType: rec.contentType,
            positionSeconds: position,
            durationSeconds: duration,
            title: existing?.title ?? rec.title,
            posterURL: existing?.posterURL,
            updatedAt: Date().timeIntervalSince1970)
        try? container.catalogStore.savePosition(pos)
    }

    private func step(_ delta: Int) {
        let target = index + delta
        guard items.indices.contains(target) else { return }
        index = target
    }

    /// Fin de titre : on enchaîne ; au dernier titre on ferme le lecteur.
    private func goToNextOrClose() {
        if index < items.count - 1 { index += 1 } else { onClose() }
    }
}
