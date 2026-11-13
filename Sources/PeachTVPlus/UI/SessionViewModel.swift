import Foundation
import Combine

/// État de session + routage (login ↔ shell) et gestion multi-listes. Expose au-dessus du
/// `XtreamRepository` une surface observable pour SwiftUI. Applique le garde-fou **HTTPS
/// d'abord** : un serveur HTTP exige le consentement explicite avant tout envoi d'identifiants.
@MainActor
final class SessionViewModel: ObservableObject {

    @Published private(set) var isLoggedIn: Bool
    @Published private(set) var playlists: [Playlist]
    @Published private(set) var activeId: String?
    @Published var isWorking = false
    @Published var errorMessage: String?
    /// Passe à `true` quand un serveur HTTP non consenti bloque le login → l'UI demande l'accord.
    @Published var pendingCleartextHost: String?

    let container: AppContainer
    private var repo: XtreamRepository { container.repository }

    init(container: AppContainer) {
        self.container = container
        self.isLoggedIn = container.repository.isLoggedIn
        self.playlists = container.repository.playlists
        self.activeId = container.repository.activePlaylist?.id
    }

    /// Connexion / ajout d'une liste. `allowCleartext` accorde le consentement HTTP pour l'hôte.
    @discardableResult
    func login(server: String, username: String, password: String, allowCleartext: Bool = false) async -> Bool {
        errorMessage = nil
        guard let creds = XtreamCredentials.normalize(server: server, username: username, password: password) else {
            errorMessage = "Adresse de serveur invalide."
            return false
        }

        if !creds.isSecure, let host = creds.host {
            if container.consent.hasConsented(host: host) || allowCleartext {
                container.consent.grant(host: host)
            } else {
                pendingCleartextHost = host
                return false
            }
        }

        isWorking = true
        defer { isWorking = false }

        let result = await repo.login(creds)
        switch result {
        case .success:
            container.refreshVault()
            refresh()
            return true
        case .invalidCredentials:
            errorMessage = "Identifiants invalides."
        case .expired:
            errorMessage = "Cet abonnement est expiré."
        case .networkError(let message):
            errorMessage = "Problème réseau : \(message)"
        }
        return false
    }

    func switchTo(_ id: String) {
        repo.setActivePlaylist(id)
        container.refreshVault()
        refresh()
    }

    func remove(_ id: String) {
        container.removePlaylist(id)
        refresh()
    }

    func logout() {
        for playlist in repo.playlists { container.removePlaylist(playlist.id) }
        refresh()
    }

    private func refresh() {
        isLoggedIn = repo.isLoggedIn
        playlists = repo.playlists
        activeId = repo.activePlaylist?.id
    }
}
