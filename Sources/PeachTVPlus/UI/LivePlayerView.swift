import SwiftUI

/// Enveloppe du lecteur **Direct** : tient l'index de chaîne courant dans la liste filtrée,
/// reconstruit la requête au **glissé horizontal** (chaîne ±1), alimente « maintenant/ensuite »
/// (EPG court), ouvre le **guide horaire** et joue le **rattrapage** sans quitter le lecteur.
struct LivePlayerView: View {
    let channels: [LiveChannel]
    let container: AppContainer
    var onClose: () -> Void

    @State private var index: Int
    @State private var nowNext: NowNext?
    @State private var showGuide = false
    @State private var catchup: PlaybackRequest?   // non nil = lecture rattrapage en cours

    init(channels: [LiveChannel], startIndex: Int, container: AppContainer, onClose: @escaping () -> Void) {
        self.channels = channels
        self.container = container
        self.onClose = onClose
        _index = State(initialValue: startIndex)
    }

    private var current: LiveChannel? {
        channels.indices.contains(index) ? channels[index] : nil
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let catchup {
                // Rattrapage : lecteur VOD-like (scrub), fermeture = retour au direct.
                PlayerView(request: catchup, onClose: { self.catchup = nil })
                    .id(catchup.url)
            } else if let current, let request = liveRequest(current) {
                PlayerView(
                    request: request,
                    nowNext: nowNext,
                    onClose: onClose,
                    onChangeChannel: changeChannel,
                    channelLogoURL: current.iconURL,
                    onShowGuide: { showGuide = true }
                )
                .id(current.id)                       // relance le lecteur sur la nouvelle chaîne
                .task(id: current.id) { await loadEpg(for: current) }
            } else {
                Button("Fermer", action: onClose).tint(.white)
            }
        }
        .sheet(isPresented: $showGuide) {
            if let current {
                EpgGuideView(channel: current, container: container) { req in
                    showGuide = false
                    catchup = req                     // bascule le lecteur sur le rattrapage
                }
            }
        }
    }

    private func liveRequest(_ c: LiveChannel) -> PlaybackRequest? {
        container.activeFactory.map { PlaybackURLBuilder.live(c, factory: $0) }
    }

    private func changeChannel(_ step: Int) {
        let n = channels.count
        guard n > 0 else { return }
        index = ((index + step) % n + n) % n          // circulaire, protégé du modulo négatif
    }

    private func loadEpg(for channel: LiveChannel) async {
        let progs = await container.repository.shortEpg(streamId: channel.id, limit: 2)
        if let now = progs.first, !now.title.isEmpty {
            nowNext = NowNext(now: now.title, next: progs.dropFirst().first?.title)
        } else {
            nowNext = nil
        }
    }
}
