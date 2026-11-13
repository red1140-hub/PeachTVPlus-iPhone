import SwiftUI

@MainActor
final class LiveViewModel: ObservableObject {
    @Published var categories: [Category] = []
    @Published var channels: [LiveChannel] = []
    @Published var selectedCategoryId: String?
    @Published var isLoading = false

    private let container: AppContainer
    init(container: AppContainer) { self.container = container }

    func loadInitial() async {
        guard channels.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        var cats = (try? container.catalogStore.categories(type: .live)) ?? []
        if cats.isEmpty {
            await container.catalogSync.sync()
            cats = (try? container.catalogStore.categories(type: .live)) ?? []
        }
        categories = cats
        reloadChannels()
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        await container.catalogSync.sync()
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
}

struct LiveView: View {
    @StateObject private var vm: LiveViewModel
    @State private var presentation: PlayerPresentation?

    init(container: AppContainer) {
        _vm = StateObject(wrappedValue: LiveViewModel(container: container))
    }

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.channels.isEmpty {
                    ProgressView("Chargement du catalogue…")
                } else if vm.channels.isEmpty {
                    ContentUnavailableView("Aucune chaîne",
                                           systemImage: "tv",
                                           description: Text("Tirez pour rafraîchir le catalogue."))
                } else {
                    channelList
                }
            }
            .navigationTitle("Direct")
            .toolbar { categoryMenu }
            .task { await vm.loadInitial() }
            .refreshable { await vm.refresh() }
            .fullScreenCover(item: $presentation) { p in
                PlayerView(request: p.request, onClose: { presentation = nil })
            }
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

    private var categoryMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Toutes les chaînes") { vm.select(nil) }
                Divider()
                ForEach(vm.categories) { cat in
                    Button(cat.name) { vm.select(cat.id) }
                }
            } label: {
                Label(vm.selectedCategoryName, systemImage: "line.3.horizontal.decrease.circle")
            }
        }
    }
}
