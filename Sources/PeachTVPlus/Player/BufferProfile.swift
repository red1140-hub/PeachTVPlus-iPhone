import Foundation

/// Trois crans de bufferisation **compréhensibles** (pas des millisecondes), appliqués
/// différemment à chaque moteur. Live démarre « Équilibré » côté latence, VOD force un buffer
/// avant plus large ; le cran choisi **module** ces bases. `preferredForwardBufferDuration = 0`
/// est proscrit (ambigu). Voir `docs/reliability-and-qa.md §1.1`.
enum BufferProfile: String, CaseIterable, Equatable {
    case lowLatency     // coller au direct, re-démarrer vite
    case balanced       // défaut
    case antiStutter    // bufferiser large, tolérer un débit instable

    static let `default`: BufferProfile = .balanced

    /// Buffer avant explicite (secondes), selon Live vs VOD. Jamais 0.
    func forwardBufferSeconds(isLive: Bool) -> Double {
        switch self {
        case .lowLatency:  return 2
        case .balanced:    return isLive ? 5 : 8
        case .antiStutter: return isLive ? 15 : 30
        }
    }

    /// `AVPlayer.automaticallyWaitsToMinimizeStalling`. En faible latence on désactive l'attente
    /// (re-démarrage rapide, quitte à sacrifier un peu de fluidité).
    var waitsToMinimizeStalling: Bool {
        self != .lowLatency
    }

    /// Option VLC `--network-caching` (ms) — consommée par `VLCPlayerEngine` en M3b.
    var vlcNetworkCachingMs: Int {
        switch self {
        case .lowLatency:  return 1000
        case .balanced:    return 3000
        case .antiStutter: return 8000
        }
    }
}
