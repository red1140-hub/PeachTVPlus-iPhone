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

    /// Catégories synthétiques : « Favoris » et « Toutes » (ids sentinelles).
    static let favoritesCategoryId = "__fav__"
    static let allId = "__all__"

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
            // « Favoris » : résolution directe par ids (plus de troncature à 5000 — une
            // chaîne favorite au-delà n'apparaissait sinon pas sur les gros catalogues).
            source = ((try? container.catalogStore.liveChannels(ids: Array(favoriteIds))) ?? [])
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } else {
            let cid = (selectedCategoryId == Self.allId) ? nil : selectedCategoryId
            source = (try? container.catalogStore.liveChannels(categoryId: cid, limit: 1000)) ?? []
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

    /// Catégories du menu : « Favoris » (si favoris), « Toutes », puis les catégories réelles.
    var menuCategories: [Category] {
        var out: [Category] = []
        if !favoriteIds.isEmpty {
            out.append(Category(id: Self.favoritesCategoryId, name: "★ Favoris", contentType: .live))
        }
        out.append(Category(id: Self.allId, name: "Toutes les chaînes", contentType: .live))
        out.append(contentsOf: categories)
        return out
    }

    var selectedCategoryName: String {
        if selectedCategoryId == Self.favoritesCategoryId { return "★ Favoris" }
        if selectedCategoryId == nil || selectedCategoryId == Self.allId { return "Toutes les chaînes" }
        return categories.first { $0.id == selectedCategoryId }?.name ?? "Catégorie"
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
    @State private var presentation: LivePresentation?     // lecture Direct (par index)
    @State private var catchup: PlayerPresentation?        // rattrapage lancé depuis la grille
    @State private var selectedId: String?                 // chaîne dont on affiche la grille
    @Environment(\.horizontalSizeClass) private var hSize
    private let container: AppContainer

    init(container: AppContainer) {
        self.container = container
        _vm = StateObject(wrappedValue: LiveViewModel(container: container))
    }

    /// Colonne de chaînes plus large sur iPad / paysage, compacte sur iPhone portrait.
    private var columnWidth: CGFloat { hSize == .regular ? 190 : 122 }

    private var selectedChannel: LiveChannel? {
        vm.channels.first { $0.id == selectedId }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !vm.categories.isEmpty {
                    CategoryDropdown(selectedName: vm.selectedCategoryName,
                                     entries: vm.menuCategories,
                                     selectedId: vm.selectedCategoryId,
                                     onSelect: { vm.select($0); syncSelection() })
                    Divider()
                }
                content
            }
            .toolbar(.hidden, for: .navigationBar)
            .task { await vm.loadInitial(); syncSelection() }
            .onChange(of: vm.channels) { _, _ in syncSelection() }
            .fullScreenCover(item: $presentation, onDismiss: { vm.refreshState() }) { p in
                LivePlayerView(channels: vm.channels, startIndex: p.index,
                               container: container, onClose: { presentation = nil })
            }
            .fullScreenCover(item: $catchup) { p in
                PlayerView(request: p.request, onClose: { catchup = nil })
            }
        }
    }

    /// Garde la chaîne sélectionnée valide : conserve l'actuelle si encore présente, sinon
    /// retombe sur la première de la liste filtrée.
    private func syncSelection() {
        if let id = selectedId, vm.channels.contains(where: { $0.id == id }) { return }
        selectedId = vm.channels.first?.id
    }

    @ViewBuilder private var content: some View {
        if vm.isLoading && vm.channels.isEmpty {
            ProgressView("Chargement du catalogue…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.channels.isEmpty {
            emptyState
        } else {
            HStack(spacing: 0) {
                channelColumn
                    .frame(width: columnWidth)
                    .background(Color(white: 0.06))
                Divider()
                epgPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: Colonne de chaînes (boutons : logo fixe + nom déroulant)

    private var channelColumn: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(vm.channels) { channel in
                    channelCell(channel)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
        }
        .refreshable { await vm.refresh() }
    }

    private func channelCell(_ channel: LiveChannel) -> some View {
        let isSelected = channel.id == selectedId
        return Button {
            selectedId = channel.id
        } label: {
            VStack(spacing: 5) {
                ChannelLogo(url: channel.iconURL)
                    .frame(width: 46, height: 46)
                    .overlay(alignment: .topTrailing) {
                        if vm.isFavorite(channel) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 9)).foregroundStyle(Theme.ratingStar)
                                .padding(2).background(.black.opacity(0.6), in: Circle())
                                .offset(x: 4, y: -4)
                        }
                    }
                MarqueeText(text: channel.name, font: .caption)
                    .frame(maxWidth: .infinity)
                if channel.hasArchive {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 9)).foregroundStyle(Theme.archiveBadge)
                        .accessibilityLabel("Rattrapage disponible")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .background(isSelected ? Theme.accent.opacity(0.22) : Color.white.opacity(0.04),
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Theme.accent : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
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

    // MARK: Panneau de droite — grille horaire de la chaîne sélectionnée

    @ViewBuilder private var epgPanel: some View {
        if let channel = selectedChannel {
            ChannelEpgPanel(
                channel: channel,
                container: container,
                onWatchLive: {
                    if let idx = vm.channels.firstIndex(of: channel) {
                        presentation = LivePresentation(index: idx)
                    }
                },
                onCatchup: { catchup = PlayerPresentation(request: $0) }
            )
            .id(channel.id)
        } else {
            ContentUnavailableView("Choisissez une chaîne",
                                   systemImage: "hand.tap",
                                   description: Text("La grille horaire s'affiche ici."))
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
}

/// Panneau **grille horaire** d'une chaîne (à droite du Direct). Charge l'EPG du jour **à la
/// demande** (`fullEpg`), met en tête la chaîne + un bouton **Regarder**, surligne l'émission
/// en cours, et offre le **rattrapage** sur les émissions passées (chaîne à archive).
private struct ChannelEpgPanel: View {
    let channel: LiveChannel
    let container: AppContainer
    var onWatchLive: () -> Void
    var onCatchup: (PlaybackRequest) -> Void

    @State private var programmes: [EpgProgramme] = []
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Group {
                if isLoading {
                    ProgressView("Chargement du guide…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if programmes.isEmpty {
                    ContentUnavailableView("Guide indisponible",
                                           systemImage: "calendar",
                                           description: Text("Aucune donnée horaire pour cette chaîne."))
                } else {
                    List(programmes) { prog in
                        EpgProgrammeRow(prog: prog, channel: channel,
                                        container: container, onCatchup: onCatchup)
                    }
                    .listStyle(.plain)
                }
            }
        }
        .task(id: channel.id) { await load() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ChannelLogo(url: channel.iconURL).frame(width: 40, height: 40)
            Text(channel.name).font(.headline).lineLimit(2)
            Spacer(minLength: 8)
            Button(action: onWatchLive) {
                Label("Regarder", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(Theme.accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func load() async {
        isLoading = true
        let p = await container.repository.fullEpg(streamId: channel.id)
        programmes = p.sorted { ($0.start ?? .distantPast) < ($1.start ?? .distantPast) }
        isLoading = false
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
