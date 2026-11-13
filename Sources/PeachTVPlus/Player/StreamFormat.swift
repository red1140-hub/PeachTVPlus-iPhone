import Foundation

/// Moteur de lecture à utiliser pour un flux.
enum PlaybackEngineKind: Equatable {
    case avPlayer   // HLS (.m3u8) / mp4 — natif, AirPlay, PiP
    case vlc        // MPEG-TS (.ts ou sans extension) / HEVC / AC3 — MobileVLCKit (M3b)
}

/// Choix de moteur **sans se fier à l'extension seule** (les URLs Live Xtream en sont souvent
/// dépourvues) + construction de l'URL alternative pour la bascule (la même chaîne existe
/// souvent en `.ts` **et** `.m3u8`). Logique pure, testable sans moteur réel. Voir
/// `docs/reliability-and-qa.md §1.6` et `docs/PORT-SPEC.md §7.1`.
enum StreamFormat {

    private static let hlsExts: Set<String> = ["m3u8"]
    private static let avProgressiveExts: Set<String> = ["mp4", "m4v", "mov"]
    // .ts / .mkv / sans extension / inconnu → VLC (AVPlayer ne lit pas le TS brut, et VLC
    // couvre nativement HEVC/AC3/DTS que VOD AVPlayer peut refuser).

    /// Moteur **préféré** au premier essai.
    static func preferredEngine(for url: URL) -> PlaybackEngineKind {
        let ext = url.pathExtension.lowercased()
        if hlsExts.contains(ext) { return .avPlayer }
        if avProgressiveExts.contains(ext) { return .avPlayer }
        return .vlc   // .ts, .mkv, sans extension, inconnu
    }

    /// URL alternative pour la bascule Live : permute `.ts` ↔ `.m3u8`. `nil` si non applicable
    /// (VOD progressif, extension inconnue) → dans ce cas on bascule de moteur sans changer d'URL.
    static func alternateURL(for url: URL) -> URL? {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "ts":   return url.deletingPathExtension().appendingPathExtension("m3u8")
        case "m3u8": return url.deletingPathExtension().appendingPathExtension("ts")
        default:     return nil
        }
    }

    /// Cible de bascule après un échec conteneur/codec : l'**autre** moteur, et l'URL
    /// alternative si elle existe (sinon la même URL sur l'autre moteur).
    static func fallback(for url: URL, from kind: PlaybackEngineKind) -> (url: URL, kind: PlaybackEngineKind) {
        let other: PlaybackEngineKind = (kind == .avPlayer) ? .vlc : .avPlayer
        return (alternateURL(for: url) ?? url, other)
    }
}

/// Verrou « une seule bascule par tentative » — évite le ping-pong infini AVPlayer↔VLC
/// (`docs/reliability-and-qa.md §1.6`). Remis à zéro à chaque nouveau `prepare` réussi.
struct PlaybackFallbackGuard {
    private(set) var hasSwitched = false

    /// Autorise une bascule une seule fois ; renvoie la cible ou `nil` si déjà basculé.
    mutating func switchTarget(for url: URL, from kind: PlaybackEngineKind)
        -> (url: URL, kind: PlaybackEngineKind)? {
        guard !hasSwitched else { return nil }
        hasSwitched = true
        return StreamFormat.fallback(for: url, from: kind)
    }

    mutating func reset() { hasSwitched = false }
}
