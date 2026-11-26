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
    /// EPG du jour par chaîne, chargé **à la demande** quand la ligne apparaît (jamais en bloc).
    @Published private(set) var epgByChannel: [String: [EpgProgramme]] = [:]
    private var epgLoading: Set<String> = []

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
        epgByChannel = [:]
        reloadChannels()
    }

    func select(_ id: String?) {
        selectedCategoryId = id
        epgByChannel = [:]            // changement de catégorie → on relâche l'EPG en cache
        reloadChannels()
    }

    /// Charge l'EPG d'une chaîne **une seule fois** (idempotent), quand sa ligne apparaît.
    func loadEpg(for channel: LiveChannel) async {
        let id = channel.id
        if epgByChannel[id] != nil || epgLoading.contains(id) { return }
        epgLoading.insert(id)
        let progs = await container.repository.fullEpg(streamId: id)
        epgByChannel[id] = progs.sorted { ($0.start ?? .distantPast) < ($1.start ?? .distantPast) }
        epgLoading.remove(id)
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
    @State private var catchup: PlayerPresentation?        // rattrapage lancé depuis une case
    @State private var infoProg: ProgrammeInfo?            // détails d'une émission (feuille)
    @State private var pendingCatchup: PlaybackRequest?    // rattrapage à lancer APRÈS fermeture de la feuille
    @State private var pendingPlayIndex: Int?              // « Regarder en direct » à lancer APRÈS fermeture
    @Environment(\.horizontalSizeClass) private var hSize
    private let container: AppContainer

    init(container: AppContainer) {
        self.container = container
        _vm = StateObject(wrappedValue: LiveViewModel(container: container))
    }

    /// Colonne de chaînes plus large sur iPad / paysage, compacte sur iPhone portrait.
    private var columnWidth: CGFloat { hSize == .regular ? 190 : 122 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !vm.categories.isEmpty {
                    CategoryDropdown(selectedName: vm.selectedCategoryName,
                                     entries: vm.menuCategories,
                                     selectedId: vm.selectedCategoryId,
                                     onSelect: { vm.select($0) })
                    Divider()
                }
                content
            }
            .toolbar(.hidden, for: .navigationBar)
            .task { await vm.loadInitial() }
            .fullScreenCover(item: $presentation, onDismiss: { vm.refreshState() }) { p in
                LivePlayerView(channels: vm.channels, startIndex: p.index,
                               container: container, onClose: { presentation = nil })
            }
            .fullScreenCover(item: $catchup) { p in
                PlayerView(request: p.request, onClose: { catchup = nil })
            }
            .sheet(item: $infoProg, onDismiss: {
                // Lancé APRÈS la fermeture de la feuille : évite qu'un plein écran présenté
                // pendant la fermeture soit ignoré par SwiftUI. (Un seul des deux est posé.)
                if let i = pendingPlayIndex { pendingPlayIndex = nil; presentation = LivePresentation(index: i) }
                else if let r = pendingCatchup { pendingCatchup = nil; catchup = PlayerPresentation(request: r) }
            }) { info in
                programmeSheet(info)
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
            guideGrid
        }
    }

    // MARK: Grille façon téléviseur — chaînes à gauche, axe de temps PARTAGÉ à droite

    /// Échelle : largeur par minute + hauteur fixe d'une ligne (colonne gauche et lignes droite alignées).
    private var pxPerMinute: CGFloat { 3 }
    private var rowHeight: CGFloat { 66 }

    /// Fenêtre = la journée courante (00:00 → 24:00). Les cases sont positionnées à leur heure
    /// réelle → axe **partagé** par toutes les chaînes, et le trait « maintenant » est vertical
    /// et cohérent d'une ligne à l'autre.
    private func dayStart() -> Date { Calendar.current.startOfDay(for: Date()) }
    private func xPos(_ date: Date, from start: Date) -> CGFloat {
        CGFloat(date.timeIntervalSince(start) / 60) * pxPerMinute
    }

    private var guideGrid: some View {
        let start = dayStart()
        let canvasW = CGFloat(24 * 60) * pxPerMinute      // 24 h
        let nowX = xPos(Date(), from: start)
        return ScrollViewReader { proxy in
            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 0) {
                    channelColumn
                    Divider()
                    ScrollView(.horizontal, showsIndicators: true) {
                        LazyVStack(spacing: 0) {
                            ForEach(vm.channels) { channel in
                                timelineRow(channel, start: start, canvasW: canvasW, nowX: nowX)
                                Divider().frame(width: canvasW)
                            }
                        }
                    }
                }
            }
            .refreshable { await vm.refresh() }
            .onAppear { proxy.scrollTo("now", anchor: .center) }   // ouvre sur l'heure actuelle
        }
    }

    // MARK: Colonne de chaînes (gauche, toujours visible — ne défile pas horizontalement)

    private var channelColumn: some View {
        LazyVStack(spacing: 0) {
            ForEach(vm.channels) { channel in
                channelCell(channel)
                    .frame(width: columnWidth, height: rowHeight)
                    .background(Color(white: 0.06))
                Divider().frame(width: columnWidth)
            }
        }
        .frame(width: columnWidth)
    }

    /// Cellule chaîne compacte (hauteur fixe) : logo + nom déroulant + badge archive ;
    /// **tap = regarder**, appui long = favori / cacher.
    private func channelCell(_ channel: LiveChannel) -> some View {
        Button {
            if let idx = vm.channels.firstIndex(of: channel) {
                presentation = LivePresentation(index: idx)
            }
        } label: {
            HStack(spacing: 6) {
                ChannelLogo(url: channel.iconURL)
                    .frame(width: 34, height: 34)
                    .overlay(alignment: .topTrailing) {
                        if vm.isFavorite(channel) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 8)).foregroundStyle(Theme.ratingStar)
                                .padding(1.5).background(.black.opacity(0.6), in: Circle())
                                .offset(x: 3, y: -3)
                        }
                    }
                VStack(alignment: .leading, spacing: 2) {
                    MarqueeText(text: channel.name, font: .caption2)
                    if channel.hasArchive {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 8)).foregroundStyle(Theme.archiveBadge)
                            .accessibilityLabel("Rattrapage disponible")
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
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

    // MARK: Ligne horaire d'une chaîne (cases positionnées par le temps + trait « maintenant »)

    /// Cases positionnées à leur heure réelle sur un canevas de largeur fixe (`canvasW`) partagé
    /// par toutes les chaînes. EPG chargé à la demande quand la ligne apparaît. Le trait
    /// « maintenant » est dessiné par ligne (donc continu d'une ligne à l'autre).
    private func timelineRow(_ channel: LiveChannel, start: Date, canvasW: CGFloat, nowX: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            if let progs = vm.epgByChannel[channel.id] {
                ForEach(progs) { prog in
                    if let f = cellFrame(prog, start: start, canvasW: canvasW) {
                        programmeChip(prog, channel: channel, isNow: EpgFormat.isNow(prog))
                            .frame(width: f.width, height: rowHeight - 6)
                            .offset(x: f.x, y: 3)
                    }
                }
            } else {
                ProgressView().offset(x: max(2, nowX - 10), y: rowHeight / 2 - 10)
            }
            Rectangle().fill(Theme.liveNow).frame(width: 2, height: rowHeight)
                .offset(x: nowX).allowsHitTesting(false)
            if channel.id == vm.channels.first?.id {
                Color.clear.frame(width: 1, height: 1).offset(x: nowX).id("now")
            }
        }
        .frame(width: canvasW, height: rowHeight, alignment: .topLeading)
        .clipped()
        .task(id: channel.id) { await vm.loadEpg(for: channel) }
    }

    /// Position + largeur d'une case selon son heure (nil si hors fenêtre ou bornes inconnues).
    private func cellFrame(_ prog: EpgProgramme, start: Date, canvasW: CGFloat) -> (x: CGFloat, width: CGFloat)? {
        guard let s = prog.start, let e = prog.end else { return nil }
        let x0 = max(0, xPos(s, from: start))
        let x1 = min(canvasW, xPos(e, from: start))
        guard x1 > x0 else { return nil }
        return (x0, max(2, x1 - x0))
    }

    /// Case d'émission : plage horaire + titre ; surlignée si **en cours**. Tap → feuille de détails.
    private func programmeChip(_ prog: EpgProgramme, channel: LiveChannel, isNow: Bool) -> some View {
        Button {
            infoProg = ProgrammeInfo(prog: prog, channel: channel)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(EpgFormat.timeRange(prog))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(isNow ? Theme.liveNow : .secondary)
                Text(prog.title.isEmpty ? "(Sans titre)" : prog.title)
                    .font(.caption).lineLimit(2)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6).padding(.vertical, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(isNow ? Theme.liveNow.opacity(0.18) : Color.white.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isNow ? Theme.liveNow : Color.white.opacity(0.08),
                            lineWidth: isNow ? 1.5 : 0.5)
            )
            .clipped()
        }
        .buttonStyle(.plain)
    }

    /// Feuille de détails d'une émission : réutilise `EpgProgrammeRow` (horaire, EN COURS,
    /// titre, résumé, **Rattrapage**, **IMDb**). Le rattrapage ferme la feuille et lance le lecteur.
    private func programmeSheet(_ info: ProgrammeInfo) -> some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        if let idx = vm.channels.firstIndex(of: info.channel) { pendingPlayIndex = idx }
                        infoProg = nil
                    } label: {
                        Label("Regarder en direct", systemImage: "play.fill")
                    }
                    .tint(Theme.accent)
                }
                EpgProgrammeRow(prog: info.prog, channel: info.channel, container: container,
                                onCatchup: { req in pendingCatchup = req; infoProg = nil })
            }
            .listStyle(.plain)
            .navigationTitle(info.channel.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fermer") { infoProg = nil } }
            }
        }
        .presentationDetents([.medium, .large])
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

/// Détails d'une émission à présenter en feuille (depuis une case de la grille Direct).
struct ProgrammeInfo: Identifiable {
    let id = UUID()
    let prog: EpgProgramme
    let channel: LiveChannel
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
