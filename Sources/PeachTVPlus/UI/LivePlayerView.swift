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
    @State private var dayEpg: [EpgProgramme] = [] // grille du jour de la chaîne courante (portrait)
    @State private var loadingEpg = false          // distingue « en chargement » de « aucune programmation »

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
        GeometryReader { geo in
            // Portrait = vidéo en haut + grille horaire de la chaîne en dessous ; paysage = plein écran.
            let portrait = geo.size.height >= geo.size.width
            let guideAction: (() -> Void)? = portrait ? nil : { showGuide = true }
            ZStack {
                Color.black.ignoresSafeArea()
                if let catchup {
                    // Rattrapage : lecteur VOD-like (scrub), fermeture = retour au direct.
                    PlayerView(request: catchup, onClose: { self.catchup = nil })
                        .id(catchup.url)
                } else if let current, let request = liveRequest(current) {
                    VStack(spacing: 0) {
                        // MÊME instance de PlayerView dans les deux orientations (frame / safe-area
                        // conditionnels, pas de if/else structurel) → pas de relance à la rotation.
                        PlayerView(
                            request: request,
                            nowNext: nowNext,
                            onClose: onClose,
                            onChangeChannel: changeChannel,
                            channelLogoURL: current.iconURL,
                            onShowGuide: guideAction
                        )
                        .id(current.id)                       // relance le lecteur sur la nouvelle chaîne
                        .frame(maxWidth: .infinity,
                               maxHeight: portrait ? geo.size.width * 9 / 16 : .infinity)
                        .ignoresSafeArea(edges: portrait ? [] : .all)
                        .task(id: current.id) { await loadEpg(for: current) }

                        if portrait {
                            channelSchedule(current)
                        }
                    }
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
    }

    /// Portrait : grille horaire du jour de la chaîne en cours, sous la vidéo. Réutilise
    /// `EpgProgrammeRow` (plage horaire, EN COURS, titre, résumé, Rattrapage, IMDb).
    @ViewBuilder private func channelSchedule(_ channel: LiveChannel) -> some View {
        if loadingEpg {
            VStack { Spacer(); ProgressView().tint(.white); Spacer() }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
        } else if dayEpg.isEmpty {
            VStack { Spacer()
                Text("Aucune programmation pour cette chaîne")
                    .font(.footnote).foregroundStyle(.secondary)
                Spacer() }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
        } else {
            List(dayEpg) { prog in
                EpgProgrammeRow(prog: prog, channel: channel, container: container,
                                onCatchup: { req in catchup = req })
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.black)
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

    /// Charge la grille du jour de la chaîne (portrait) et en dérive « maintenant / ensuite ».
    private func loadEpg(for channel: LiveChannel) async {
        dayEpg = []                                   // évite d'afficher la grille de l'ancienne chaîne
        loadingEpg = true
        defer { loadingEpg = false }
        let progs = (await container.repository.fullEpg(streamId: channel.id))
            .sorted { ($0.start ?? .distantPast) < ($1.start ?? .distantPast) }
        dayEpg = progs
        if let idx = progs.firstIndex(where: { EpgFormat.isNow($0) }) {
            nowNext = NowNext(now: progs[idx].title,
                              next: idx + 1 < progs.count ? progs[idx + 1].title : nil)
        } else if let first = progs.first(where: { !$0.title.isEmpty }) {
            nowNext = NowNext(now: first.title, next: nil)
        } else {
            nowNext = nil
        }
    }
}
