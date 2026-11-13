import Foundation

/// Identifiants d'un abonnement Xtream Codes, avec URL serveur **normalisée**.
///
/// `serverUrl` est toujours réduit à l'origine `scheme://host[:port]` (sans slash
/// ni path final). `description` ne divulgue **jamais** le mot de passe (anti-fuite
/// dans les logs — voir `RedactingLogger`).
struct XtreamCredentials: Equatable, Hashable {
    let serverUrl: String
    let username: String
    let password: String

    /// `true` si l'origine est en HTTPS.
    var isSecure: Bool { serverUrl.lowercased().hasPrefix("https://") }

    /// Hôte de l'origine (pour le garde-fou d'hôte sur la réinjection d'identifiants).
    var host: String? { URLComponents(string: serverUrl)?.host }

    /// Normalise une saisie utilisateur libre en identifiants exploitables.
    ///
    /// Accepte : `serveur.com:8080`, `http://serveur.com:8080/`, une URL
    /// `…/player_api.php?…` complète → tout est réduit à l'origine. Renvoie `nil`
    /// si aucun hôte n'est trouvable.
    static func normalize(server raw: String, username: String, password: String) -> XtreamCredentials? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.contains("://") { s = "http://" + s }

        guard let comps = URLComponents(string: s),
              let host = comps.host, !host.isEmpty else { return nil }

        let scheme = (comps.scheme?.lowercased() == "https") ? "https" : "http"
        var origin = "\(scheme)://\(host)"
        if let port = comps.port { origin += ":\(port)" }

        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let pass = password.trimmingCharacters(in: .whitespacesAndNewlines)

        return XtreamCredentials(serverUrl: origin, username: user, password: pass)
    }
}

extension XtreamCredentials: CustomStringConvertible {
    var description: String {
        "XtreamCredentials(server=\(serverUrl), user=\(username), pass=***)"
    }
}
