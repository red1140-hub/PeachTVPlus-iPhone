import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Piste sélectionnable (audio ou sous-titre), neutre vis-à-vis du moteur. `id` est l'identifiant
/// propre au moteur (index d'option AVPlayer, ou index de piste VLC) ; `name` est libellé affichable.
struct MediaTrack: Identifiable, Equatable, Hashable {
    enum Kind: Equatable, Hashable { case audio, subtitle }
    let id: Int
    let name: String
    let kind: Kind
}

/// État de lecture observable, commun aux deux moteurs (AVPlayer, VLC).
enum PlaybackState: Equatable {
    case idle
    case preparing
    case buffering
    case playing
    case paused
    case ended
    case failed(PlaybackError)
}

/// Abstraction de moteur de lecture : AVPlayer (HLS/mp4) et MobileVLCKit (TS/HEVC/AC3, M3b)
/// s'y conforment. Le reste de l'app ne connaît que ce protocole → la bascule de moteur
/// (`StreamFormat.fallback`) se fait sans dépendre d'une implémentation. Voir `docs/PORT-SPEC.md §7.1`.
protocol VideoEngine: AnyObject {
    var kind: PlaybackEngineKind { get }
    var state: PlaybackState { get }

    /// Notifié à chaque changement d'état (sur le thread principal).
    var onStateChange: ((PlaybackState) -> Void)? { get set }

    /// Prépare un flux. `isLive` module le buffer (profil) et la politique de retry.
    func prepare(url: URL, profile: BufferProfile, isLive: Bool)

    func play()
    func pause()
    func stop()

    /// Déplacement (VOD). Ignoré en Live par le lecteur (pas de scrub libre en direct).
    func seek(to seconds: Double)

    /// Position / durée courantes (secondes) — `nil` si indisponible (Live sans fenêtre).
    var currentTimeSeconds: Double? { get }
    var durationSeconds: Double? { get }

    /// Pistes audio / sous-titres disponibles + sélection courante (VOD surtout). Implémentées
    /// par défaut à « vide » (voir extension) pour les moteurs qui ne les gèrent pas.
    var audioTracks: [MediaTrack] { get }
    var subtitleTracks: [MediaTrack] { get }
    var currentAudioTrackId: Int? { get }
    var currentSubtitleTrackId: Int? { get }
    func selectAudioTrack(_ id: Int)
    /// `nil` désactive les sous-titres.
    func selectSubtitleTrack(_ id: Int?)

    #if canImport(UIKit)
    /// Attache la surface de rendu du moteur à `view` (couche `AVPlayerLayer` pour AVPlayer,
    /// `drawable` pour VLC). Appelé par le coordinateur avant `prepare` ; à la bascule de
    /// moteur, l'ancienne surface est vidée puis le nouveau moteur s'y attache. Voir `PlaybackCoordinator`.
    func attach(to view: UIView)
    #endif
}

/// Défauts : un moteur qui ne gère pas les pistes (ex. repli VLC-absent) n'a rien à implémenter.
extension VideoEngine {
    var audioTracks: [MediaTrack] { [] }
    var subtitleTracks: [MediaTrack] { [] }
    var currentAudioTrackId: Int? { nil }
    var currentSubtitleTrackId: Int? { nil }
    func selectAudioTrack(_ id: Int) {}
    func selectSubtitleTrack(_ id: Int?) {}
}
