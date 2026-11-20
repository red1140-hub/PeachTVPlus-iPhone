import Foundation
import AVFoundation
#if canImport(UIKit)
import UIKit

/// Vue dont la couche racine **est** l'`AVPlayerLayer` : elle se redimensionne seule
/// (rotation, Split View iPad, plein écran) sans qu'on gère de `frame` à la main.
private final class AVPlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
#endif

/// Moteur natif (HLS `.m3u8` / mp4) : AirPlay, PiP et pistes audio/sous-titres « gratuits ».
/// Le TS brut et HEVC/AC3 relèvent de `VLCPlayerEngine` (M3b) — ici on reste sur AVFoundation.
///
/// Les callbacks KVO peuvent arriver hors du thread principal → on republie l'état sur
/// `DispatchQueue.main`. Non testé en CI (nécessite un flux réel/device) ; la logique testable
/// vit dans `StreamFormat`, `PlaybackRetryPolicy`, `PlaybackError`, etc.
final class AVPlayerEngine: VideoEngine {

    let kind: PlaybackEngineKind = .avPlayer

    private(set) var state: PlaybackState = .idle {
        didSet { if state != oldValue { onStateChange?(state) } }
    }
    var onStateChange: ((PlaybackState) -> Void)?

    private let player = AVPlayer()
    private var itemStatusObs: NSKeyValueObservation?
    private var timeControlObs: NSKeyValueObservation?
    private var isLive = false

    /// Groupes de sélection chargés **de façon asynchrone** quand l'item devient lisible
    /// (API non dépréciée `loadMediaSelectionGroup(for:)`), puis mis en cache pour des accès synchrones.
    private var audioGroup: AVMediaSelectionGroup?
    private var legibleGroup: AVMediaSelectionGroup?

    init() {
        player.automaticallyWaitsToMinimizeStalling = true
    }

    deinit {
        itemStatusObs?.invalidate()
        timeControlObs?.invalidate()
    }

    func prepare(url: URL, profile: BufferProfile, isLive: Bool) {
        self.isLive = isLive
        setState(.preparing)

        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = profile.forwardBufferSeconds(isLive: isLive)
        player.automaticallyWaitsToMinimizeStalling = profile.waitsToMinimizeStalling

        observe(item)
        player.replaceCurrentItem(with: item)
    }

    func play() { player.play() }

    func pause() {
        player.pause()
        setState(.paused)
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        itemStatusObs?.invalidate(); itemStatusObs = nil
        audioGroup = nil; legibleGroup = nil
        setState(.idle)
    }

    func seek(to seconds: Double) {
        guard !isLive else { return }   // pas de scrub libre en direct
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
    }

    var currentTimeSeconds: Double? {
        let t = player.currentTime().seconds
        return t.isFinite ? t : nil
    }

    var durationSeconds: Double? {
        guard let d = player.currentItem?.duration.seconds, d.isFinite, d > 0 else { return nil }
        return d
    }

    // MARK: - Pistes audio / sous-titres (via groupes de sélection média)

    var audioTracks: [MediaTrack] {
        guard let g = audioGroup else { return [] }
        return g.options.enumerated().map { MediaTrack(id: $0.offset, name: $0.element.displayName, kind: .audio) }
    }

    var subtitleTracks: [MediaTrack] {
        guard let g = legibleGroup else { return [] }
        return g.options.enumerated().map { MediaTrack(id: $0.offset, name: $0.element.displayName, kind: .subtitle) }
    }

    var currentAudioTrackId: Int? { selectedIndex(in: audioGroup) }
    var currentSubtitleTrackId: Int? { selectedIndex(in: legibleGroup) }

    func selectAudioTrack(_ id: Int) {
        guard let item = player.currentItem, let g = audioGroup, g.options.indices.contains(id) else { return }
        item.selectMediaOption(g.options[id], in: g)
    }

    func selectSubtitleTrack(_ id: Int?) {
        guard let item = player.currentItem, let g = legibleGroup else { return }
        if let id, g.options.indices.contains(id) {
            item.selectMediaOption(g.options[id], in: g)
        } else {
            item.selectMediaOption(nil, in: g)   // désactive les sous-titres
        }
    }

    private func selectedIndex(in group: AVMediaSelectionGroup?) -> Int? {
        guard let item = player.currentItem, let group,
              let sel = item.currentMediaSelection.selectedMediaOption(in: group),
              let idx = group.options.firstIndex(of: sel) else { return nil }
        return idx
    }

    private func loadSelectionGroups(for item: AVPlayerItem) {
        let asset = item.asset
        Task { [weak self] in
            let audio = try? await asset.loadMediaSelectionGroup(for: .audible)
            let legible = try? await asset.loadMediaSelectionGroup(for: .legible)
            await MainActor.run {
                self?.audioGroup = audio
                self?.legibleGroup = legible
            }
        }
    }

    #if canImport(UIKit)
    func attach(to view: UIView) {
        let layerView = AVPlayerLayerView()
        layerView.playerLayer.player = player
        layerView.playerLayer.videoGravity = .resizeAspect
        layerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(layerView)
        NSLayoutConstraint.activate([
            layerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            layerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            layerView.topAnchor.constraint(equalTo: view.topAnchor),
            layerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
    #endif

    // MARK: - Observation

    private func observe(_ item: AVPlayerItem) {
        itemStatusObs = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            let status = item.status
            let error = item.error
            DispatchQueue.main.async {
                guard let self else { return }
                switch status {
                case .failed:       self.setState(.failed(Self.mapError(error)))
                case .readyToPlay:
                    if self.state == .preparing { self.setState(.buffering) }
                    self.loadSelectionGroups(for: item)
                default:            break
                }
            }
        }
        timeControlObs = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let status = player.timeControlStatus
            DispatchQueue.main.async {
                guard let self else { return }
                switch status {
                case .playing:
                    self.setState(.playing)
                case .waitingToPlayAtSpecifiedRate:
                    if self.state != .playing { self.setState(.buffering) }
                case .paused:
                    if self.state != .idle, self.state != .ended { self.setState(.paused) }
                @unknown default:
                    break
                }
            }
        }
    }

    private func setState(_ new: PlaybackState) { state = new }

    private static func mapError(_ error: Error?) -> PlaybackError {
        if let urlError = error as? URLError {
            return PlaybackError.classify(urlErrorCode: urlError.code)
        }
        // Échec d'item sans URLError = le plus souvent format/codec non supporté par AVPlayer
        // → le coordinateur (M3b) tentera la bascule VLC avant de montrer ce message.
        return .unsupported
    }
}
