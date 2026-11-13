import Foundation

/// Fabrique toutes les URLs Xtream pour un serveur donné.
///
/// - URLs d'API : `…/player_api.php?username=&password=&action=…` (query, identifiants
///   percent-encodés par `URLComponents`).
/// - URLs de flux : `…/live|movie|series/{user}/{pass}/{id}.{ext}` (path).
/// - Téléchargements : forme **masquée** avec le marqueur `__cred__` à la place de
///   user/pass (aucun secret persisté) ; réinjection à la volée avec **garde-fou d'hôte**
///   (ne réinjecte que si l'hôte de l'URL correspond au serveur des identifiants).
struct XtreamURLFactory {
    enum StreamKind: String { case live, movie, series }

    static let credentialMarker = "__cred__"

    let credentials: XtreamCredentials
    private let origin: URL

    init(credentials: XtreamCredentials) {
        self.credentials = credentials
        // `serverUrl` est une origine normalisée valide ; repli littéral sûr sinon.
        self.origin = URL(string: credentials.serverUrl) ?? URL(string: "http://invalid.local")!
    }

    // MARK: - API (query)

    private func api(_ extra: [URLQueryItem]) -> URL {
        var comps = URLComponents(url: origin, resolvingAgainstBaseURL: false) ?? URLComponents()
        comps.path = "/player_api.php"
        comps.queryItems = [
            URLQueryItem(name: "username", value: credentials.username),
            URLQueryItem(name: "password", value: credentials.password)
        ] + extra
        return comps.url ?? origin
    }

    /// Authentification + infos compte (pas d'`action`).
    func auth() -> URL { api([]) }

    func action(_ name: String, categoryId: String? = nil) -> URL {
        var items = [URLQueryItem(name: "action", value: name)]
        if let categoryId { items.append(URLQueryItem(name: "category_id", value: categoryId)) }
        return api(items)
    }

    func vodInfo(vodId: String) -> URL {
        api([URLQueryItem(name: "action", value: "get_vod_info"),
             URLQueryItem(name: "vod_id", value: vodId)])
    }

    func seriesInfo(seriesId: String) -> URL {
        api([URLQueryItem(name: "action", value: "get_series_info"),
             URLQueryItem(name: "series_id", value: seriesId)])
    }

    func shortEpg(streamId: String, limit: Int = 4) -> URL {
        api([URLQueryItem(name: "action", value: "get_short_epg"),
             URLQueryItem(name: "stream_id", value: streamId),
             URLQueryItem(name: "limit", value: String(limit))])
    }

    func simpleDataTable(streamId: String) -> URL {
        api([URLQueryItem(name: "action", value: "get_simple_data_table"),
             URLQueryItem(name: "stream_id", value: streamId)])
    }

    // MARK: - Flux (path, identifiants réels)

    func liveStreamURL(id: String, ext: String = "ts") -> URL {
        streamURL(kind: .live, user: credentials.username, pass: credentials.password, id: id, ext: ext)
    }

    func movieURL(id: String, ext: String) -> URL {
        streamURL(kind: .movie, user: credentials.username, pass: credentials.password, id: id, ext: ext)
    }

    func seriesEpisodeURL(episodeId: String, ext: String) -> URL {
        streamURL(kind: .series, user: credentials.username, pass: credentials.password, id: episodeId, ext: ext)
    }

    /// Rattrapage/timeshift. `start` est formaté en **fuseau local** par défaut
    /// (réserve si le serveur est dans un autre fuseau — voir PORT-SPEC §3).
    func timeshiftURL(streamId: String, durationMinutes: Int, start: Date,
                      timeZone: TimeZone = .current) -> URL {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = timeZone
        fmt.dateFormat = "yyyy-MM-dd:HH-mm"
        return origin
            .appendingPathComponent("timeshift")
            .appendingPathComponent(credentials.username)
            .appendingPathComponent(credentials.password)
            .appendingPathComponent(String(durationMinutes))
            .appendingPathComponent(fmt.string(from: start))
            .appendingPathComponent("\(streamId).ts")
    }

    private func streamURL(kind: StreamKind, user: String, pass: String, id: String, ext: String) -> URL {
        origin
            .appendingPathComponent(kind.rawValue)
            .appendingPathComponent(user)
            .appendingPathComponent(pass)
            .appendingPathComponent("\(id).\(ext)")
    }

    // MARK: - Téléchargement : forme masquée + réinjection

    /// URL de flux **sans identifiants** (marqueur `__cred__`) — c'est cette forme qu'on
    /// persiste (clé de cache, table `downloads`), jamais l'URL avec secrets.
    func maskedStreamURLString(kind: StreamKind, id: String, ext: String) -> String {
        streamURL(kind: kind, user: Self.credentialMarker, pass: Self.credentialMarker, id: id, ext: ext)
            .absoluteString
    }

    /// Réinjecte les identifiants dans une URL masquée **uniquement si l'hôte (et le port)
    /// correspondent** à `credentials` — anti-fuite d'identifiants vers un autre serveur.
    static func reinjectCredentials(into masked: String, credentials: XtreamCredentials) -> URL? {
        guard var comps = URLComponents(string: masked), let maskedHost = comps.host,
              let credComps = URLComponents(string: credentials.serverUrl), let credHost = credComps.host,
              maskedHost.caseInsensitiveCompare(credHost) == .orderedSame,
              comps.port == credComps.port else { return nil }

        var parts = comps.path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        let kinds: Set<String> = ["live", "movie", "series", "timeshift"]
        guard let ki = parts.firstIndex(where: { kinds.contains($0.lowercased()) }),
              ki + 2 < parts.count,
              parts[ki + 1] == credentialMarker,
              parts[ki + 2] == credentialMarker else { return nil }

        parts[ki + 1] = credentials.username
        parts[ki + 2] = credentials.password
        comps.path = parts.joined(separator: "/")
        return comps.url
    }
}
