import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(VLCKitSPM)
import VLCKitSPM
#endif

// Moteur VLC (MobileVLCKit empaqueté en « VLCKitSPM », M3b) : lit le MPEG-TS brut, HEVC,
// AC3/DTS qu'AVPlayer refuse. Conforme au même `VideoEngine` que `AVPlayerEngine` → le
// coordinateur bascule de l'un à l'autre sans rien connaître de l'implémentation.
//
// ⚠️ Non testé en CI (nécessite un flux réel + une sortie vidéo). La logique de bascule et de
// retry est, elle, testée via `PlaybackCoordinator` avec des moteurs factices.

#if canImport(VLCKitSPM)

final class VLCPlayerEngine: NSObject, VideoEngine {

    let kind: PlaybackEngineKind = .vlc

    private(set) var state: PlaybackState = .idle {
        didSet { if state != oldValue { onStateChange?(state) } }
    }
    var onStateChange: ((PlaybackState) -> Void)?

    private let player = VLCMediaPlayer()
    private var isLive = false

    override init() {
        super.init()
        player.delegate = self
    }

    func prepare(url: URL, profile: BufferProfile, isLive: Bool) {
        self.isLive = isLive
        setState(.preparing)
        let media = VLCMedia(url: url)
        // `--network-caching` en option **par média** (préfixe « : ») — module le buffer VLC
        // selon le profil choisi (faible latence ↔ anti-saccade). Voir `BufferProfile`.
        media.addOption(":network-caching=\(profile.vlcNetworkCachingMs)")
        player.media = media
    }

    func play() { player.play() }

    func pause() {
        if player.canPause { player.pause() }
        setState(.paused)
    }

    func stop() {
        player.stop()
        setState(.idle)
    }

    func seek(to seconds: Double) {
        guard !isLive, player.isSeekable else { return }   // pas de scrub libre en direct
        player.time = VLCTime(int: Int32(seconds * 1000))
    }

    var currentTimeSeconds: Double? {
        let ms = player.time.intValue              // VLCTime non-optionnel ; ms, 0 si indisponible
        return ms > 0 ? Double(ms) / 1000 : nil
    }

    var durationSeconds: Double? {
        let ms = player.media?.length.intValue ?? 0
        return ms > 0 ? Double(ms) / 1000 : nil
    }

    // MARK: - Pistes audio / sous-titres (index VLC)

    var audioTracks: [MediaTrack] {
        zip(intArray(player.audioTrackIndexes), strArray(player.audioTrackNames))
            .map { MediaTrack(id: $0.0, name: $0.1, kind: .audio) }
    }

    var subtitleTracks: [MediaTrack] {
        // On retire l'entrée « Disable » (index -1) de VLC : la désactivation est offerte à part.
        zip(intArray(player.videoSubTitlesIndexes), strArray(player.videoSubTitlesNames))
            .filter { $0.0 >= 0 }
            .map { MediaTrack(id: $0.0, name: $0.1, kind: .subtitle) }
    }

    var currentAudioTrackId: Int? {
        let i = Int(player.currentAudioTrackIndex); return i >= 0 ? i : nil
    }
    var currentSubtitleTrackId: Int? {
        let i = Int(player.currentVideoSubTitleIndex); return i >= 0 ? i : nil
    }

    func selectAudioTrack(_ id: Int) { player.currentAudioTrackIndex = Int32(id) }
    func selectSubtitleTrack(_ id: Int?) { player.currentVideoSubTitleIndex = Int32(id ?? -1) }

    private func intArray(_ a: [Any]?) -> [Int] { (a ?? []).compactMap { ($0 as? NSNumber)?.intValue } }
    private func strArray(_ a: [Any]?) -> [String] { (a ?? []).map { "\($0)" } }

    #if canImport(UIKit)
    func attach(to view: UIView) {
        player.drawable = view
    }
    #endif

    private func setState(_ new: PlaybackState) { state = new }
}

extension VLCPlayerEngine: VLCMediaPlayerDelegate {

    @objc func mediaPlayerStateChanged(_ aNotification: Notification) {
        let mapped: PlaybackState
        switch player.state {
        case .opening:    mapped = .preparing
        case .buffering:  mapped = player.isPlaying ? .playing : .buffering
        case .playing:    mapped = .playing
        case .paused:     mapped = .paused
        case .stopped:    mapped = .idle
        case .ended:      mapped = .ended
        case .error:      mapped = .failed(.unsupported)  // conteneur/codec illisible → bascule
        case .esAdded:    mapped = state                  // pistes détectées : pas d'état visible
        @unknown default: mapped = state
        }
        // VLCKit notifie sur le thread principal ; on reste défensif par cohérence avec AVPlayerEngine.
        if Thread.isMainThread {
            setState(mapped)
        } else {
            DispatchQueue.main.async { [weak self] in self?.setState(mapped) }
        }
    }
}

#else

/// Repli : `VLCKitSPM` n'a pas pu être résolu/importé. Moteur-fantôme qui échoue aussitôt
/// pour que le coordinateur bascule vers AVPlayer — l'app reste liable et fonctionnelle
/// (sans lecture TS brut) même si la résolution SPM de VLCKit casse en CI.
final class VLCPlayerEngine: VideoEngine {

    let kind: PlaybackEngineKind = .vlc

    private(set) var state: PlaybackState = .idle {
        didSet { if state != oldValue { onStateChange?(state) } }
    }
    var onStateChange: ((PlaybackState) -> Void)?

    func prepare(url: URL, profile: BufferProfile, isLive: Bool) {
        state = .failed(.unsupported)
    }

    func play() {}
    func pause() {}
    func stop() { state = .idle }
    func seek(to seconds: Double) {}

    var currentTimeSeconds: Double? { nil }
    var durationSeconds: Double? { nil }

    #if canImport(UIKit)
    func attach(to view: UIView) {}
    #endif
}

#endif
