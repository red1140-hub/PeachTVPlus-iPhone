import SwiftUI

@MainActor
final class HiddenChannelsViewModel: ObservableObject {
    /// Chaînes cachées résolues à leur fiche (nom + logo) depuis le catalogue courant.
    @Published var channels: [LiveChannel] = []
    /// Ids cachés qui ne sont plus dans le catalogue courant (serveur changé, catégorie partie…).
    @Published var unknownIds: [String] = []

    private let container: AppContainer
    init(container: AppContainer) { self.container = container }

    private var playlistId: String? { container.repository.activePlaylist?.id }

    func reload() {
        guard let pid = playlistId else { channels = []; unknownIds = []; return }
        let hidden = (try? container.catalogStore.hiddenStreamIds(playlistId: pid)) ?? []
        // Résolution par ids (plus de troncature à 5000 : une chaîne cachée au-delà
        // s'affichait « Chaîne 12345 » sans nom ni logo sur les gros catalogues).
        let found = (try? container.catalogStore.liveChannels(ids: Array(hidden))) ?? []
        let byId = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        channels = hidden.compactMap { byId[$0] }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        unknownIds = hidden.filter { byId[$0] == nil }.sorted()
    }

    var isEmpty: Bool { channels.isEmpty && unknownIds.isEmpty }

    func restore(_ streamId: String) {
        guard let pid = playlistId else { return }
        try? container.catalogStore.unhide(playlistId: pid, streamId: streamId)
        reload()
    }

    func restoreAll() {
        guard let pid = playlistId else { return }
        try? container.catalogStore.restoreAllHidden(playlistId: pid)
        reload()
    }
}

/// Réglages → **Chaînes cachées** : liste les chaînes masquées (appui long dans le Direct) et
/// permet de les **restaurer**, une par une ou toutes d'un coup. Reprend le comportement Android.
struct HiddenChannelsView: View {
    @StateObject private var vm: HiddenChannelsViewModel

    init(container: AppContainer) {
        _vm = StateObject(wrappedValue: HiddenChannelsViewModel(container: container))
    }

    var body: some View {
        List {
            if vm.isEmpty {
                ContentUnavailableView("Aucune chaîne cachée",
                                       systemImage: "eye",
                                       description: Text("Masquez une chaîne par un appui long dans le Direct."))
            } else {
                Section {
                    ForEach(vm.channels) { ch in
                        row(name: ch.name, iconURL: ch.iconURL, streamId: ch.id)
                    }
                    ForEach(vm.unknownIds, id: \.self) { id in
                        row(name: "Chaîne \(id)", iconURL: nil, streamId: id)
                    }
                }
                Section {
                    Button { vm.restoreAll() } label: {
                        Label("Tout restaurer", systemImage: "eye")
                    }
                    .tint(Theme.accent)
                }
            }
        }
        .navigationTitle("Chaînes cachées")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { vm.reload() }
    }

    private func row(name: String, iconURL: String?, streamId: String) -> some View {
        HStack(spacing: 12) {
            ChannelLogo(url: iconURL).frame(width: 40, height: 40)
            Text(name).lineLimit(1)
            Spacer()
            Button("Restaurer") { vm.restore(streamId) }
                .buttonStyle(.borderless)
                .tint(Theme.accent)
        }
    }
}
