import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Fabrique de moteurs — injectable pour tester le coordinateur avec des moteurs factices
/// (sans AVFoundation ni VLC, sans flux réel).
protocol VideoEngineFactory {
    func makeEngine(for kind: PlaybackEngineKind) -> VideoEngine
}

/// Fabrique réelle : AVPlayer pour HLS/mp4, VLC pour le reste.
struct DefaultVideoEngineFactory: VideoEngineFactory {
    func makeEngine(for kind: PlaybackEngineKind) -> VideoEngine {
        switch kind {
        case .avPlayer: return AVPlayerEngine()
        case .vlc:      return VLCPlayerEngine()
        }
    }
}

/// **Orchestrateur unique de la lecture** : choisit le moteur, bascule AVPlayer↔VLC **une seule
/// fois** sur un échec de format/conteneur (`PlaybackFallbackGuard`), retente les erreurs réseau
/// transitoires en back-off (`PlaybackRetryController`), et remonte une erreur claire sinon. Le
/// reste de l'app (écran lecteur M5) ne parle qu'à ce coordinateur, jamais aux moteurs.
///
/// À utiliser **depuis le thread principal** (publie l'état pour SwiftUI ; les moteurs notifient
/// déjà sur le thread principal). Logique de bascule/retry testée via `PlaybackCoordinatorTests`.
/// Voir `docs/reliability-and-qa.md §1.3/§1.6` et `docs/PORT-SPEC.md §7.1`.
final class PlaybackCoordinator: ObservableObject {

    @Published private(set) var state: PlaybackState = .idle
    @Published private(set) var engineKind: PlaybackEngineKind = .avPlayer

    private let factory: VideoEngineFactory
    /// Planificateur du délai de retry — injectable pour tester sans attendre un vrai timer.
    private let scheduleAfter: (TimeInterval, @escaping () -> Void) -> Void

    private var engine: VideoEngine?
    private var fallback = PlaybackFallbackGuard()
    private var retry: PlaybackRetryController?
    private var currentURL: URL?
    private var isLive = false
    private var profile: BufferProfile = .default
    /// Jeton d'invalidation : chaque (re)démarrage/arrêt le change → un retry programmé devenu
    /// obsolète (nouvelle lecture, bascule, stop) se désamorce tout seul.
    private var epoch = 0

    #if canImport(UIKit)
    private weak var renderSurface: UIView?
    #endif

    init(factory: VideoEngineFactory = DefaultVideoEngineFactory(),
         scheduleAfter: @escaping (TimeInterval, @escaping () -> Void) -> Void =
            { delay, work in DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work) }) {
        self.factory = factory
        self.scheduleAfter = scheduleAfter
    }

    // MARK: - Surface de rendu

    #if canImport(UIKit)
    /// Donne au coordinateur la vue où afficher la vidéo. Rattachée automatiquement à chaque
    /// bascule de moteur (l'ancienne surface est vidée au préalable).
    func attachRenderSurface(_ view: UIView) {
        renderSurface = view
        if let engine { mountSurface(for: engine) }
    }

    private func mountSurface(for engine: VideoEngine) {
        guard let renderSurface else { return }
        renderSurface.subviews.forEach { $0.removeFromSuperview() }
        renderSurface.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        engine.attach(to: renderSurface)
    }
    #endif

    // MARK: - Commandes

    /// Démarre une nouvelle lecture. Réinitialise la bascule et le compteur de retry.
    func play(url: URL, isLive: Bool, profile: BufferProfile = .default) {
        fallback.reset()
        retry = PlaybackRetryController(isLive: isLive)
        currentURL = url
        self.isLive = isLive
        self.profile = profile
        start(kind: StreamFormat.preferredEngine(for: url))
    }

    func resume() { engine?.play() }
    func pause() { engine?.pause() }

    func stop() {
        epoch &+= 1                 // invalide tout retry en attente
        engine?.onStateChange = nil
        engine?.stop()
        engine = nil
        state = .idle
    }

    func seek(to seconds: Double) { engine?.seek(to: seconds) }

    var currentTimeSeconds: Double? { engine?.currentTimeSeconds }
    var durationSeconds: Double? { engine?.durationSeconds }

    // MARK: - Démarrage d'un moteur

    private func start(kind: PlaybackEngineKind) {
        guard let url = currentURL else { return }
        epoch &+= 1                 // invalide les retry programmés avant ce (re)démarrage

        engine?.onStateChange = nil
        engine?.stop()

        let newEngine = factory.makeEngine(for: kind)
        engine = newEngine
        engineKind = kind
        newEngine.onStateChange = { [weak self] newState in self?.handle(newState) }

        #if canImport(UIKit)
        mountSurface(for: newEngine)
        #endif

        state = .preparing
        newEngine.prepare(url: url, profile: profile, isLive: isLive)
        newEngine.play()
    }

    // MARK: - États & erreurs

    private func handle(_ newState: PlaybackState) {
        switch newState {
        case .playing:
            retry?.reset()          // lecture stable → on oublie l'historique d'échecs
            state = .playing
        case .failed(let error):
            handleFailure(error)
        default:
            state = newState
        }
    }

    private enum FailureClass { case bascule, retry, permanent, silent }

    /// Oriente une erreur : bascule de moteur, retry réseau, erreur définitive, ou silencieux.
    private func classify(_ error: PlaybackError) -> FailureClass {
        switch error.kind {
        case .unsupportedFormat, .unreadableContainer:
            return .bascule
        case .noConnection, .serverUnreachable, .serverSlow, .unknown:
            return .retry
        case .accessDenied, .streamUnavailable, .cleartextBlocked, .schemeRejected:
            return .permanent
        case .behindLive:
            return .silent
        }
    }

    private func handleFailure(_ error: PlaybackError) {
        switch classify(error) {
        case .bascule:
            guard let url = currentURL,
                  let target = fallback.switchTarget(for: url, from: engineKind) else {
                // Déjà basculé une fois → les deux moteurs ont échoué.
                state = .failed(.unsupported)
                return
            }
            currentURL = target.url
            start(kind: target.kind)

        case .retry:
            guard let delay = retry?.registerFailure(statusCode: nil) else {
                state = .failed(error)      // tentatives épuisées
                return
            }
            let token = epoch
            let kind = engineKind
            scheduleAfter(delay) { [weak self] in
                guard let self, self.epoch == token else { return }   // obsolète → on abandonne
                self.start(kind: kind)
            }

        case .permanent:
            state = .failed(error)

        case .silent:
            break   // ex. décrochage direct : géré par le moteur, pas de message
        }
    }
}
