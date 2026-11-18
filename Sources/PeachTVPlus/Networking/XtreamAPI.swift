import Foundation

enum APIError: Error, Equatable {
    case invalidResponse
    case http(Int)
    case emptyResponse
    case decoding(String)
    case transport(String)
}

extension APIError {
    /// Message court en français, **sûr à afficher** (aucun secret), décrivant la panne.
    /// Sert à remonter une vraie cause à l'écran au lieu d'un « Aucune chaîne » muet.
    var frenchMessage: String {
        switch self {
        case .transport(let message): return "Connexion au serveur impossible (\(message))."
        case .http(401), .http(403):  return "Accès refusé — identifiants ou abonnement."
        case .http(let code):         return "Erreur du serveur (code \(code))."
        case .emptyResponse:          return "Le serveur n'a renvoyé aucune donnée."
        case .invalidResponse:        return "Réponse inattendue du serveur."
        case .decoding:               return "Le serveur a renvoyé des données illisibles."
        }
    }
}

/// Enveloppe de décodage **tolérante par élément** : un élément de tableau illisible (champ
/// requis manquant ou de type incompatible) devient `nil` au lieu de faire échouer le décodage
/// de **toute** la liste. On décode `[FailableDecodable<T>]` puis on `compactMap` les `base`
/// non nuls — c'est le « parsing défensif par élément » exigé (modèle Android).
struct FailableDecodable<Base: Decodable>: Decodable {
    let base: Base?
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        base = try? container.decode(Base.self)
    }
}

/// Accès réseau bas niveau à un serveur Xtream (un serveur = une instance).
/// `async/await` sur `URLSession` ; `session` est injectable (tests via `URLProtocol`).
protocol XtreamAPIProtocol {
    func authenticate() async throws -> AuthResponseDTO
    func liveCategories() async throws -> [CategoryDTO]
    func liveStreams(categoryId: String?) async throws -> [LiveStreamDTO]
    func vodCategories() async throws -> [CategoryDTO]
    func movies(categoryId: String?) async throws -> [MovieStreamDTO]
    func seriesCategories() async throws -> [CategoryDTO]
    func seriesList(categoryId: String?) async throws -> [SeriesStreamDTO]
    func vodInfo(vodId: String) async throws -> VodInfoResponseDTO
    func seriesInfo(seriesId: String) async throws -> SeriesInfoResponseDTO
    func shortEpg(streamId: String, limit: Int) async throws -> ShortEpgResponseDTO
}

struct XtreamAPI: XtreamAPIProtocol {
    let urlFactory: XtreamURLFactory
    let session: URLSession
    var userAgent: String = "PeachTVPlus/0.1 (iOS)"

    private let decoder = JSONDecoder()

    init(urlFactory: XtreamURLFactory, session: URLSession = .shared) {
        self.urlFactory = urlFactory
        self.session = session
    }

    func authenticate() async throws -> AuthResponseDTO {
        try await get(urlFactory.auth())
    }

    func liveCategories() async throws -> [CategoryDTO] {
        try await getArray(urlFactory.action("get_live_categories"))
    }

    func liveStreams(categoryId: String?) async throws -> [LiveStreamDTO] {
        try await getArray(urlFactory.action("get_live_streams", categoryId: categoryId))
    }

    func vodCategories() async throws -> [CategoryDTO] {
        try await getArray(urlFactory.action("get_vod_categories"))
    }

    func movies(categoryId: String?) async throws -> [MovieStreamDTO] {
        try await getArray(urlFactory.action("get_vod_streams", categoryId: categoryId))
    }

    func seriesCategories() async throws -> [CategoryDTO] {
        try await getArray(urlFactory.action("get_series_categories"))
    }

    func seriesList(categoryId: String?) async throws -> [SeriesStreamDTO] {
        try await getArray(urlFactory.action("get_series", categoryId: categoryId))
    }

    func vodInfo(vodId: String) async throws -> VodInfoResponseDTO {
        try await get(urlFactory.vodInfo(vodId: vodId))
    }

    func seriesInfo(seriesId: String) async throws -> SeriesInfoResponseDTO {
        try await get(urlFactory.seriesInfo(seriesId: seriesId))
    }

    func shortEpg(streamId: String, limit: Int = 4) async throws -> ShortEpgResponseDTO {
        try await get(urlFactory.shortEpg(streamId: streamId, limit: limit))
    }

    /// EPG complet du jour pour une chaîne (`get_simple_data_table`) — sert au guide horaire +
    /// rattrapage. Même forme de réponse que `shortEpg` (`epg_listings`). Appel **à la demande**
    /// (jamais en masse sur toutes les chaînes : risque de bannissement, leçon Android).
    func simpleDataTable(streamId: String) async throws -> ShortEpgResponseDTO {
        try await get(urlFactory.simpleDataTable(streamId: streamId))
    }

    // MARK: - Transport

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            RedactingLogger.error("Transport error for \(url.absoluteString): \(error.localizedDescription)")
            throw APIError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw APIError.http(http.statusCode) }
        guard !data.isEmpty else { throw APIError.emptyResponse }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            // L'URL est passée par le logger redacteur (username=/password= masqués) ; l'erreur
            // de décodage ne contient que le chemin de clés, pas la donnée brute ni de secret.
            RedactingLogger.error("Décodage échoué pour \(url.absoluteString) — \(error)")
            throw APIError.decoding(String(describing: error))
        }
    }

    /// Décodage **tolérant par élément** d'un tableau : ignore les éléments illisibles au lieu
    /// de faire échouer toute la liste (un seul objet sans `stream_id`/`category_id` ne doit
    /// plus vider le catalogue entier). Les erreurs de transport / HTTP / réponse vide, elles,
    /// continuent de **remonter** via `get` (pour être affichées, pas transformées en « vide »).
    private func getArray<Element: Decodable>(_ url: URL) async throws -> [Element] {
        let wrapped: [FailableDecodable<Element>] = try await get(url)
        let elements = wrapped.compactMap(\.base)
        let dropped = wrapped.count - elements.count
        if dropped > 0 {
            RedactingLogger.error("Décodage liste : \(dropped)/\(wrapped.count) élément(s) ignoré(s) (champ requis manquant/incompatible).")
        }
        return elements
    }
}
