import Foundation

/// Allowlist de schémas (anti-SSRF local). Toute URL de flux / téléchargement / image est
/// validée **avant** usage : schéma ∈ {`http`, `https`} **et** hôte présent. On rejette
/// `file:`, `data:`, `content:`, `javascript:`, `ftp:`… — sinon un serveur hostile ferait
/// lire un fichier local. Voir `docs/security.md §4.4`.
enum URLGuard {
    static let allowedSchemes: Set<String> = ["http", "https"]

    static func isPlayable(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              allowedSchemes.contains(scheme),
              url.host != nil else { return false }
        return true
    }

    static func isPlayable(_ string: String) -> Bool {
        guard let url = URL(string: string) else { return false }
        return isPlayable(url)
    }
}
