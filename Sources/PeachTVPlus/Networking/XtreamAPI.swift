import Foundation

enum APIError: Error, Equatable {
    case invalidResponse
    case http(Int)
    case emptyResponse
    case decoding(String)
    case transport(String)
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
        try await get(urlFactory.action("get_live_categories"))
    }

    func liveStreams(categoryId: String?) async throws -> [LiveStreamDTO] {
        try await get(urlFactory.action("get_live_streams", categoryId: categoryId))
    }

    func vodCategories() async throws -> [CategoryDTO] {
        try await get(urlFactory.action("get_vod_categories"))
    }

    func movies(categoryId: String?) async throws -> [MovieStreamDTO] {
        try await get(urlFactory.action("get_vod_streams", categoryId: categoryId))
    }

    func seriesCategories() async throws -> [CategoryDTO] {
        try await get(urlFactory.action("get_series_categories"))
    }

    func seriesList(categoryId: String?) async throws -> [SeriesStreamDTO] {
        try await get(urlFactory.action("get_series", categoryId: categoryId))
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
            throw APIError.decoding(String(describing: error))
        }
    }
}
