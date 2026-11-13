import Foundation

/// Persistance de l'état multi-listes. M1 = en mémoire ; M2 fournira une implémentation
/// adossée au Keychain (chiffré). Le repository ne connaît que ce protocole.
protocol PlaylistStoring: AnyObject {
    func load() -> PlaylistState
    func save(_ state: PlaylistState)
}

final class InMemoryPlaylistStore: PlaylistStoring {
    private var state: PlaylistState
    init(_ state: PlaylistState = .empty) { self.state = state }
    func load() -> PlaylistState { state }
    func save(_ state: PlaylistState) { self.state = state }
}

/// Point d'entrée data unique (login + catalogue + gestion des listes).
///
/// M1 : réseau + mapping + **multi-listes** (store mémoire, `playlistEpoch`). Le cache
/// catalogue (GRDB) et l'isolation `playlistId` des favoris/masquées arrivent en M2 ;
/// `resetForSourceChange()` y videra le cache en gardant favoris/masquées.
@MainActor
final class XtreamRepository {
    private let session: URLSession
    private let store: PlaylistStoring
    private(set) var state: PlaylistState
    private(set) var playlistEpoch: Int = 0

    init(session: URLSession = .shared, store: PlaylistStoring = InMemoryPlaylistStore()) {
        self.session = session
        self.store = store
        self.state = store.load()
    }

    // MARK: - Listes

    var playlists: [Playlist] { state.items }
    var activePlaylist: Playlist? { state.active }
    var activeCredentials: XtreamCredentials? { state.active?.credentials }
    var isLoggedIn: Bool { state.active != nil }

    func addOrActivate(_ credentials: XtreamCredentials) {
        let playlist = Playlist(credentials: credentials)
        let previous = state.activeId
        if !state.items.contains(where: { $0.id == playlist.id }) {
            state.items.append(playlist)
        }
        state.activeId = playlist.id
        if previous != playlist.id { resetForSourceChange() }
        store.save(state)
    }

    func setActivePlaylist(_ id: String) {
        guard state.activeId != id, state.items.contains(where: { $0.id == id }) else { return }
        state.activeId = id
        resetForSourceChange()
        store.save(state)
    }

    func removePlaylist(_ id: String) {
        let wasActive = (state.activeId == id)
        state.items.removeAll { $0.id == id }
        if wasActive {
            state.activeId = state.items.first?.id
            resetForSourceChange()
        }
        store.save(state)
        // M2 : purger les favoris + chaînes masquées scopés `playlistId == id`.
    }

    /// Changement de source active → le cache catalogue devient invalide. On incrémente
    /// l'epoch ; tout `refresh*` en vol capture l'epoch et **abandonne** son écriture si
    /// l'epoch a changé entre-temps (anti-données-fantômes). Favoris/masquées conservés.
    func resetForSourceChange() {
        playlistEpoch += 1
    }

    // MARK: - Login

    func login(_ credentials: XtreamCredentials, activate: Bool = true) async -> LoginResult {
        let api = XtreamAPI(urlFactory: XtreamURLFactory(credentials: credentials), session: session)
        do {
            let auth = try await api.authenticate()
            guard let info = auth.userInfo else { return .invalidCredentials }
            if info.auth?.intValue == 0 { return .invalidCredentials }
            let status = (info.status ?? "").lowercased()
            if !status.isEmpty && status != "active" { return .expired }
            let account = XtreamMapping.accountInfo(from: info)
            if activate { addOrActivate(credentials) }
            return .success(account)
        } catch let apiError as APIError {
            switch apiError {
            case .decoding, .emptyResponse, .invalidResponse:
                return .invalidCredentials
            case .http(let code):
                return (code == 401 || code == 403) ? .invalidCredentials
                                                    : .networkError("Erreur serveur (\(code))")
            case .transport(let message):
                return .networkError(message)
            }
        } catch {
            return .networkError(error.localizedDescription)
        }
    }

    // MARK: - Catalogue (M1 : fetch direct, tolérant ; cache GRDB = M2)

    private func currentAPI() -> XtreamAPI? {
        guard let credentials = activeCredentials else { return nil }
        return XtreamAPI(urlFactory: XtreamURLFactory(credentials: credentials), session: session)
    }

    func liveCategories() async -> [Category] {
        guard let api = currentAPI() else { return [] }
        return (try? await XtreamMapping.categories(from: api.liveCategories(), type: .live)) ?? []
    }

    func liveChannels(categoryId: String?) async -> [LiveChannel] {
        guard let api = currentAPI() else { return [] }
        return (try? await XtreamMapping.liveChannels(from: api.liveStreams(categoryId: categoryId))) ?? []
    }

    func vodCategories() async -> [Category] {
        guard let api = currentAPI() else { return [] }
        return (try? await XtreamMapping.categories(from: api.vodCategories(), type: .vod)) ?? []
    }

    func movies(categoryId: String?) async -> [Movie] {
        guard let api = currentAPI() else { return [] }
        return (try? await XtreamMapping.movies(from: api.movies(categoryId: categoryId))) ?? []
    }

    func seriesCategories() async -> [Category] {
        guard let api = currentAPI() else { return [] }
        return (try? await XtreamMapping.categories(from: api.seriesCategories(), type: .series)) ?? []
    }

    func seriesList(categoryId: String?) async -> [Series] {
        guard let api = currentAPI() else { return [] }
        return (try? await XtreamMapping.seriesList(from: api.seriesList(categoryId: categoryId))) ?? []
    }

    func movieDetail(for movie: Movie) async -> MovieDetail? {
        guard let api = currentAPI() else { return nil }
        guard let dto = try? await api.vodInfo(vodId: movie.id) else { return nil }
        return XtreamMapping.movieDetail(from: dto, base: movie)
    }

    func seriesDetail(for series: Series) async -> SeriesDetail? {
        guard let api = currentAPI() else { return nil }
        guard let dto = try? await api.seriesInfo(seriesId: series.id) else { return nil }
        return XtreamMapping.seriesDetail(from: dto, base: series)
    }

    func shortEpg(streamId: String, limit: Int = 4) async -> [EpgProgramme] {
        guard let api = currentAPI() else { return [] }
        guard let dto = try? await api.shortEpg(streamId: streamId, limit: limit) else { return [] }
        return XtreamMapping.epgProgrammes(from: dto)
    }
}
