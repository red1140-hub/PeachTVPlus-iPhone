import SwiftUI

@MainActor
final class LiveViewModel: ObservableObject {
    @Published var categories: [Category] = []
    @Published var channels: [LiveChannel] = []
    @Published var selectedCategoryId: String?
    @Published var isLoading = false
    @Published var syncError: String?
    @Published private(set) var favoriteIds: Set<String> = []
    @Published private(set) var hiddenIds: Set<String> = []

    /// Catégorie synthétique « Favoris » (comme Android, `"__fav__"`).
    static let favoritesCategoryId = "__fav__"

    private let container: AppContainer
    private var hasLoaded = false
    init(container: AppContainer) { self.container = container }

    private var playlistId: String? { container.repository.activePlaylist?.id }

    func loadInitial() async {
        guard !hasLoaded else { return }
        isLoading = true
        defer { isLoading = false }
        var cats = (try? container.catalogStore.categories(type: .live)) ?? []
        if cats.isEmpty {
            await container.catalogSync.sync()
            syncError = container.catalogSync.lastError
            cats = (try? container.catalogStore.categories(type: .live)) ?? []
        }
        categories = cats
        loadFavHidden()
        if selectedCategoryId == nil {
            selectedCategoryId = favoriteIds.isEmpty ? Self.defaultLiveCategory(cats)?.id
                                                     : Self.favoritesCategoryId
        }
        reloadChannels()
        if !cats.isEmpty { hasLoaded = true }   // on réessaie au prochain affichage si échec
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        await container.catalogSync.sync()
        syncError = container.catalogSync.lastError
        categories = (try? container.catalogStore.categories(type: .live)) ?? []
        loadFavHidden()
        reloadChannels()
    }

    func select(_ id: String?) {
        selectedCategoryId = id
        reloadChannels()
    }

    /// Au retour du lecteur : les favoris/masquées ont pu changer via l'appui long.
    func refreshState() { loadFavHidden(); reloadChannels() }

    private func loadFavHidden() {
        guard let pid = playlistId else { favoriteIds = []; hiddenIds = []; return }
        favoriteIds = Set(((try? container.catalogStore.favorites(playlistId: pid, contentType: .live)) ?? []).map(\.itemId))
        hiddenIds = (try? container.catalogStore.hiddenStreamIds(playlistId: pid)) ?? []
    }

    private func reloadChannels() {
        let source: [LiveChannel]
        if selectedCategoryId == Self.favoritesCategoryId {
            // « Favoris » : toutes les chaînes filtrées aux favoris.
            let every = (try? container.catalogStore.liveChannels(categoryId: nil, limit: 5000)) ?? []
            source = every.filter { favoriteIds.contains($0.id) }
        } else {
            source = (try? container.catalogStore.liveChannels(categoryId: selectedCategoryId, limit: 1000)) ?? []
        }
        channels = source.filter { !hiddenIds.contains($0.id) }   // on masque les chaînes cachées
    }

    func isFavorite(_ c: LiveChannel) -> Bool { favoriteIds.contains(c.id) }

    func toggleFavorite(_ c: LiveChannel) {
        guard let pid = playlistId else { return }
        if favoriteIds.contains(c.id) {
            try? container.catalogStore.removeFavorite(playlistId: pid, contentType: .live, itemId: c.id)
        } else {
            try? container.catalogStore.addFavorite(playlistId: pid, contentType: .live,
                                                    itemId: c.id, name: c.name, posterURL: c.iconURL)
        }
        loadFavHidden(); reloadChannels()
    }

    func hide(_ c: LiveChannel) {
        guard let pid = playlistId else { return }
        try? container.catalogStore.hide(playlistId: pid, streamId: c.id)
        loadFavHidden(); reloadChannels()
    }

    /// Catégories du menu déroulant, « Favoris » en tête si au moins un favori.
    var menuCategories: [Category] {
        var out: [Category] = []
        if !favoriteIds.isEmpty {
            out.append(Category(id: Self.favoritesCategoryId, name: "★ Favoris", contentType: .live))
        }
        out.append(contentsOf: categories)
        return out
    }

    var selectedCategoryName: String {
        if selectedCategoryId == Self.favoritesCategoryId { return "★ Favoris" }
        guard let id = selectedCategoryId else { return "Toutes les chaînes" }
        return categories.first { $0.id == id }?.name ?? "Catégorie"
    }

    /// Catégorie par défaut = **« Québec » exact** (nom nettoyé des emojis/accents == « quebec »),
    /// sinon une catégorie contenant « quebec », sinon la première. Reprise du `defaultQuebecCategory`
    /// Android — évite de tomber sur « Radio Québec ».
    static func defaultLiveCategory(_ cats: [Category]) -> Category? {
        func clean(_ s: String) -> String {
            s.lowercased()
                .folding(options: .diacriticInsensitive, locale: .current)
                .components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
        }
        return cats.first { clean($0.name) == "quebec" }
            ?? cats.first { clean($0.name).contains("quebec") }
            ?? cats.first
    }
}

/// Identifiable pour présenter le lecteur Direct à partir d'un **index** dans la liste filtrée —
/// permet le changement de chaîne au glissé horizontal (voir `LivePlayerView`).
struct LivePresentation: Identifiable {
    let id = UUID()
    let index: Int
}

struct LiveView: View {
    @StateObject private var vm: LiveViewModel
    @State private var presentation: LivePresentation?
    private let container: AppContainer

    init(container: AppContainer) {
        self.container = container
        _vm = StateObject(wrappedValue: LiveViewModel(container: container))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !vm.categories.isEmpty {
                    categoryDropdown
                    Divider()
                }
                content
            }
            .navigationTitle("Direct")
            .navigationBarTitleDisplayMode(.inline)
            .task { await vm.loadInitial() }
            .fullScreenCover(item: $presentation, onDismiss: { vm.refreshState() }) { p in
                LivePlayerView(channels: vm.channels, startIndex: p.index,
                               container: container, onClose: { presentation = nil })
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
            channelList
        }
    }

    private var channelList: some View {
        List(vm.channels) { channel in
            Button {
                if let idx = vm.channels.firstIndex(of: channel) {
                    presentation = LivePresentation(index: idx)
                }
            } label: {
                HStack(spacing: 12) {
                    ChannelLogo(url: channel.iconURL).frame(width: 44, height: 44)
                    Text(channel.name).lineLimit(1)
                    Spacer()
                    if vm.isFavorite(channel) {
                        Image(systemName: "star.fill").foregroundStyle(Theme.ratingStar).font(.caption)
                    }
                    if channel.hasArchive {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(Theme.archiveBadge)
                            .accessibilityLabel("Rattrapage disponible")
                    }
                }
            }
            .contextMenu {
                Button {
                    vm.toggleFavorite(channel)
                } label: {
                    Label(vm.isFavorite(channel) ? "Retirer des favoris" : "Ajouter aux favoris",
                          systemImage: vm.isFavorite(channel) ? "star.slash" : "star")
                }
                Button(role: .destructive) {
                    vm.hide(channel)
                } label: {
                    Label("Cacher la chaîne", systemImage: "eye.slash")
                }
            }
        }
        .listStyle(.plain)
        .refreshable { await vm.refresh() }
    }

    /// Sélecteur de catégories en **liste déroulante** (comme Android), visible en tête de liste.
    private var categoryDropdown: some View {
        Menu {
            ForEach(vm.menuCategories) { cat in
                Button { vm.select(cat.id) } label: {
                    if vm.selectedCategoryId == cat.id {
                        Label(cat.name, systemImage: "checkmark")
                    } else {
                        Text(cat.name)
                    }
                }
            }
            Divider()
            Button("Toutes les chaînes") { vm.select(nil) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                Text(vm.selectedCategoryName).lineLimit(1)
                Spacer()
                Image(systemName: "chevron.down").font(.caption)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .background(Color(white: 0.12))
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
}

/// Logo de chaîne (icône distante `iconURL`), repli sur une icône TV.
struct ChannelLogo: View {
    let url: String?
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.12))
            if let u = url.flatMap({ URL(string: $0) }) {
                AsyncImage(url: u) { image in
                    image.resizable().scaledToFit().padding(4)
                } placeholder: {
                    Image(systemName: "tv").foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "tv").foregroundStyle(.secondary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
