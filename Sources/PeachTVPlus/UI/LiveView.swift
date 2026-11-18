import SwiftUI

@MainActor
final class LiveViewModel: ObservableObject {
    @Published var categories: [Category] = []
    @Published var channels: [LiveChannel] = []
    @Published var selectedCategoryId: String?
    @Published var isLoading = false
    /// Cause réelle d'un catalogue vide (panne réseau/serveur/décodage), `nil` si tout va bien.
    @Published var syncError: String?

    private let container: AppContainer
    init(container: AppContainer) { self.container = container }

    func loadInitial() async {
        guard channels.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        var cats = (try? container.catalogStore.categories(type: .live)) ?? []
        if cats.isEmpty {
            await container.catalogSync.sync()
            syncError = container.catalogSync.lastError
            cats = (try? container.catalogStore.categories(type: .live)) ?? []
        }
        categories = cats
        if selectedCategoryId == nil { selectedCategoryId = Self.defaultLiveCategory(cats)?.id }
        reloadChannels()
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        await container.catalogSync.sync()
        syncError = container.catalogSync.lastError
        categories = (try? container.catalogStore.categories(type: .live)) ?? []
        reloadChannels()
    }

    func select(_ id: String?) {
        selectedCategoryId = id
        reloadChannels()
    }

    func request(for channel: LiveChannel) -> PlaybackRequest? {
        container.activeFactory.map { PlaybackURLBuilder.live(channel, factory: $0) }
    }

    private func reloadChannels() {
        channels = (try? container.catalogStore.liveChannels(categoryId: selectedCategoryId, limit: 300)) ?? []
    }

    var selectedCategoryName: String {
        guard let id = selectedCategoryId else { return "Toutes les chaînes" }
        return categories.first { $0.id == id }?.name ?? "Catégorie"
    }

    /// Catégorie par défaut du Direct = « Québec » (nom contenant « québec »/« quebec »),
    /// sinon la première. Reprise du `defaultQuebecCategory` Android.
    static func defaultLiveCategory(_ cats: [Category]) -> Category? {
        cats.first { $0.name.localizedCaseInsensitiveContains("québec") }
            ?? cats.first { $0.name.localizedCaseInsensitiveContains("quebec") }
            ?? cats.first
    }
}

struct LiveView: View {
    @StateObject private var vm: LiveViewModel
    @State private var presentation: PlayerPresentation?

    init(container: AppContainer) {
        _vm = StateObject(wrappedValue: LiveViewModel(container: container))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !vm.categories.isEmpty {
                    CategoryChips(categories: vm.categories,
                                  selectedId: vm.selectedCategoryId,
                                  allLabel: "Toutes",
                                  onSelect: { vm.select($0) })
                    Divider()
                }
                content
            }
            .navigationTitle("Direct")
            .navigationBarTitleDisplayMode(.inline)
            .task { await vm.loadInitial() }
            .fullScreenCover(item: $presentation) { p in
                PlayerView(request: p.request, onClose: { presentation = nil })
            }
        }
    }

    @ViewBuilder private var content: some View {
        if vm.isLoading && vm.channels.isEmpty {
            ProgressView("Chargement du catalogue…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.channels.isEmpty {
            emptyState
        } else {
            channelList.refreshable { await vm.refresh() }
        }
    }

    @ViewBuilder private var emptyState: some View {
        if let error = vm.syncError {
            ContentUnavailableView {
                Label("Catalogue indisponible", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Réessayer") { Task { await vm.refresh() } }
            }
        } else {
            ContentUnavailableView("Aucune chaîne",
                                   systemImage: "tv",
                                   description: Text("Tirez pour rafraîchir le catalogue."))
        }
    }

    private var channelList: some View {
        List(vm.channels) { channel in
            Button {
                if let request = vm.request(for: channel) {
                    presentation = PlayerPresentation(request: request)
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "tv")
                        .foregroundStyle(.secondary)
                        .frame(width: 28)
                    Text(channel.name).lineLimit(1)
                    Spacer()
                    if channel.hasArchive {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(.orange)
                            .accessibilityLabel("Rattrapage disponible")
                    }
                }
            }
        }
        .listStyle(.plain)
    }
}
