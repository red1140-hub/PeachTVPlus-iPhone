import Foundation

/// Une liste de lecture = un abonnement Xtream. L'app en gère **plusieurs** ; une
/// seule est « active » à la fois (voir `XtreamRepository`). L'`id` est déterministe
/// (dérivé de serveur+utilisateur) pour détecter les doublons à l'ajout.
struct Playlist: Identifiable, Equatable, Hashable {
    let id: String
    let credentials: XtreamCredentials

    /// Nom affiché par défaut = hôte du serveur (l'utilisateur pourra renommer en M5).
    var displayName: String { credentials.host ?? credentials.serverUrl }

    init(credentials: XtreamCredentials) {
        self.credentials = credentials
        self.id = Playlist.makeId(for: credentials)
    }

    /// Id stable pour un couple (serveur, utilisateur) — insensible à la casse de l'hôte.
    /// Hash FNV-1a **déterministe** (contrairement à `String.hashValue`, aléatoire par
    /// processus) : l'id reste identique d'un lancement à l'autre → clé de persistance
    /// fiable pour l'isolation `playlistId` en M2.
    static func makeId(for c: XtreamCredentials) -> String {
        let key = "\(c.serverUrl.lowercased())|\(c.username)"
        var hash: UInt64 = 1469598103934665603      // FNV-1a offset basis
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211            // FNV prime
        }
        return String(hash, radix: 16)
    }
}

/// État persistant du gestionnaire de listes (sérialisé en M2 dans le Keychain).
struct PlaylistState: Equatable {
    var activeId: String?
    var items: [Playlist]

    static let empty = PlaylistState(activeId: nil, items: [])

    var active: Playlist? { items.first { $0.id == activeId } }
}
