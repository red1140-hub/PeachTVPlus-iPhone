import Foundation

/// Représentation **persistée** du store multi-listes (sérialisée en un seul blob JSON,
/// chiffré au repos par le Keychain). Les modèles du domaine (`Playlist`, `XtreamCredentials`)
/// ne sont pas `Codable` à dessein (l'`id` est dérivé) : on persiste cette forme explicite.
private struct PersistedPlaylists: Codable, Equatable {
    var activeId: String?
    var items: [PersistedPlaylist]

    init(_ state: PlaylistState) {
        activeId = state.activeId
        items = state.items.map {
            PersistedPlaylist(serverUrl: $0.credentials.serverUrl,
                              username: $0.credentials.username,
                              password: $0.credentials.password)
        }
    }

    func toState() -> PlaylistState {
        let playlists = items.map {
            Playlist(credentials: XtreamCredentials(serverUrl: $0.serverUrl,
                                                    username: $0.username,
                                                    password: $0.password))
        }
        // `activeId` ne reste valide que s'il désigne encore une liste présente.
        let active = playlists.contains { $0.id == activeId } ? activeId : playlists.first?.id
        return PlaylistState(activeId: active, items: playlists)
    }
}

private struct PersistedPlaylist: Codable, Equatable {
    let serverUrl: String
    let username: String
    let password: String
}

/// Persistance **chiffrée** des listes (Keychain pur, option A de `docs/security.md §2.1`).
/// Remplace `InMemoryPlaylistStore` (M1) comme store par défaut du `XtreamRepository`.
/// Équivalent iOS du `SecureSessionStore` Tink v2 d'Android.
final class KeychainPlaylistStore: PlaylistStoring {
    private let keychain: KeychainStore
    private let account = "xtream_playlists_v2"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(keychain: KeychainStore = KeychainStore()) {
        self.keychain = keychain
    }

    func load() -> PlaylistState {
        // 1) Lecture brute. Un échec = transitoire (verrou…) → NE RIEN effacer, repartir vide.
        let data: Data?
        do {
            data = try keychain.get(account: account)
        } catch {
            RedactingLogger.error("Keychain: lecture listes échouée (transitoire) — \(error)")
            return .empty
        }
        guard let data else { return .empty }   // absence légitime (1er lancement)

        // 2) Décodage. Blob présent mais illisible = corruption PERMANENTE → effacer et repartir
        //    propre (sinon boucle d'échec au lancement). cf. §2.3.
        do {
            return try decoder.decode(PersistedPlaylists.self, from: data).toState()
        } catch {
            RedactingLogger.error("Keychain: blob listes corrompu — réinitialisation")
            try? keychain.remove(account: account)
            return .empty
        }
    }

    func save(_ state: PlaylistState) {
        do {
            let data = try encoder.encode(PersistedPlaylists(state))
            try keychain.set(data, account: account)
        } catch {
            RedactingLogger.error("Keychain: sauvegarde listes échouée — \(error)")
        }
    }

    func clear() {
        try? keychain.remove(account: account)
    }
}
