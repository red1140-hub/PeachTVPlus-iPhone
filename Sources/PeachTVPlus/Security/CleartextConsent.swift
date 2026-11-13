import Foundation

/// Garde-fou applicatif **HTTPS d'abord** : les identifiants ne partent en clair (HTTP) que
/// si l'utilisateur a **consenti pour ce serveur précis**. Décision persistée **par hôte**,
/// révocable dans les Réglages (MUST — c'était un MUST manqué côté Android, audit M2).
///
/// Le simple `host` (sans user/pass) **n'est pas un secret** → `UserDefaults` convient pour
/// la *décision* de consentement. Les **identifiants**, eux, restent au Keychain (§1).
/// Voir `docs/security.md §4.2`.
///
/// M5 : annoter `@Observable` pour que le badge « non sécurisé » réagisse en direct.
final class CleartextConsent {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func key(_ host: String) -> String { "cleartext.consent.\(host.lowercased())" }

    func hasConsented(host: String) -> Bool { defaults.bool(forKey: key(host)) }
    func grant(host: String) { defaults.set(true, forKey: key(host)) }
    func revoke(host: String) { defaults.removeObject(forKey: key(host)) }

    /// À appeler **avant** tout envoi d'identifiants. `false` ⇒ bloquer et demander le
    /// consentement. HTTPS toujours autorisé ; HTTP seulement si consenti ; tout autre
    /// schéma refusé (cf. allowlist `URLGuard`).
    func maySendCredentials(to url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        switch scheme {
        case "https": return true
        case "http":  return url.host.map { hasConsented(host: $0) } ?? false
        default:      return false
        }
    }
}
