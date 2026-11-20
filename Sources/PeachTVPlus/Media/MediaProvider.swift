import Foundation

/// Élément de média **neutre**, indépendant de sa source (IPTV, fichiers locaux, plus tard
/// Plex). L'UI n'affiche que ça ; elle ne sait jamais d'où vient le contenu.
struct MediaItem: Identifiable, Equatable, Hashable {
    let id: String
    let title: String
    var subtitle: String?
    /// Durée en secondes si connue (sinon calculée paresseusement à l'affichage).
    var duration: TimeInterval?
}

/// Source de contenu lisible par l'app. **Seul contrat** que connaissent l'UI et, via la
/// requête de lecture, le lecteur : ils ne parlent qu'à cette interface et ignorent la
/// provenance réelle du média. `LocalMediaProvider` en est la première implémentation ; la
/// même interface resservira pour Plex.
///
/// Note d'architecture : le **lecteur** est déjà agnostique de la source — il consomme une
/// `PlaybackRequest` (une simple `URL`), fabriquée par l'appelant. `resolveStreamURL` est donc
/// le point exact où une source traduit un `MediaItem` en URL lisible, sans que le lecteur en
/// sache davantage. Les écrans IPTV riches (grille EPG Direct, saisons/épisodes) conservent
/// volontairement leur présentation spécialisée : les aplatir derrière une simple liste
/// changerait leur comportement. `MediaProvider` cible la **navigation à plat** d'une
/// médiathèque (local aujourd'hui, Plex demain).
protocol MediaProvider {
    /// Liste des éléments disponibles. `async` : certaines sources énumèrent des fichiers/dossiers.
    func listItems() async -> [MediaItem]
    /// Traduit un élément en URL de flux réelle, au moment de la lecture. `nil` si introuvable.
    func resolveStreamURL(_ item: MediaItem) -> URL?
}
