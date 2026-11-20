import SwiftUI

/// Guide horaire d'**une** chaîne (EPG du jour via `get_simple_data_table`, chargé **à la
/// demande** — jamais en masse). L'émission en cours est mise en évidence ; sur une chaîne à
/// archive, les émissions **terminées** offrent le **rattrapage** (timeshift). Lien de recherche
/// IMDb par titre (l'EPG Xtream n'a pas la distribution).
struct EpgGuideView: View {
    let channel: LiveChannel
    let container: AppContainer
    /// Appelé quand l'utilisateur lance un rattrapage ; le parent présente alors le lecteur.
    var onPlayCatchup: (PlaybackRequest) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var programmes: [EpgProgramme] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Chargement du guide…")
                } else if programmes.isEmpty {
                    ContentUnavailableView("Guide indisponible",
                                           systemImage: "calendar",
                                           description: Text("Aucune donnée horaire pour cette chaîne."))
                } else {
                    list
                }
            }
            .navigationTitle(channel.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
            }
            .task { await load() }
        }
    }

    private var list: some View {
        List(programmes) { prog in
            EpgProgrammeRow(prog: prog, channel: channel, container: container,
                            onCatchup: onPlayCatchup)
        }
        .listStyle(.plain)
    }

    private func load() async {
        isLoading = true
        let p = await container.repository.fullEpg(streamId: channel.id)
        programmes = p.sorted { ($0.start ?? .distantPast) < ($1.start ?? .distantPast) }
        isLoading = false
    }
}
