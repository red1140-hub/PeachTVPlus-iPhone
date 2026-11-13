import XCTest
#if canImport(UIKit)
import UIKit
#endif
@testable import PeachTVPlus

/// Teste la logique d'orchestration du `PlaybackCoordinator` — choix du moteur, bascule unique
/// AVPlayer↔VLC, retry réseau en back-off — avec un moteur **factice** (aucun AVFoundation/VLC,
/// aucun flux réel) et un planificateur de retry piloté par le test (pas de vrai timer).
final class PlaybackCoordinatorTests: XCTestCase {

    // MARK: - Doublures

    final class FakeEngine: VideoEngine {
        let kind: PlaybackEngineKind
        private(set) var state: PlaybackState = .idle {
            didSet { if state != oldValue { onStateChange?(state) } }
        }
        var onStateChange: ((PlaybackState) -> Void)?
        private(set) var preparedURL: URL?
        private(set) var playCalled = 0
        private(set) var stopCalled = 0

        init(kind: PlaybackEngineKind) { self.kind = kind }

        func prepare(url: URL, profile: BufferProfile, isLive: Bool) {
            preparedURL = url
            state = .preparing
        }
        func play() { playCalled += 1 }
        func pause() { state = .paused }
        func stop() { stopCalled += 1 }
        func seek(to seconds: Double) {}
        var currentTimeSeconds: Double? { nil }
        var durationSeconds: Double? { nil }
        #if canImport(UIKit)
        func attach(to view: UIView) {}
        #endif

        /// Simule une notification du moteur réel vers le coordinateur.
        func emit(_ newState: PlaybackState) { state = newState }
    }

    final class FakeFactory: VideoEngineFactory {
        private(set) var created: [FakeEngine] = []
        func makeEngine(for kind: PlaybackEngineKind) -> VideoEngine {
            let engine = FakeEngine(kind: kind)
            created.append(engine)
            return engine
        }
        var last: FakeEngine { created.last! }
    }

    final class TestScheduler {
        private(set) var jobs: [() -> Void] = []
        func schedule(_ delay: TimeInterval, _ work: @escaping () -> Void) { jobs.append(work) }
        /// Déclenche le prochain retry en attente.
        func fireNext() { jobs.removeFirst()() }
        var pendingCount: Int { jobs.count }
    }

    private func makeSUT() -> (PlaybackCoordinator, FakeFactory, TestScheduler) {
        let factory = FakeFactory()
        let scheduler = TestScheduler()
        let sut = PlaybackCoordinator(factory: factory, scheduleAfter: scheduler.schedule)
        return (sut, factory, scheduler)
    }

    private let tsURL = URL(string: "http://s/live/u/p/1.ts")!
    private let mp4URL = URL(string: "http://s/movie/u/p/1.mp4")!

    private func netFail() -> PlaybackState {
        .failed(PlaybackError.classify(urlErrorCode: .notConnectedToInternet))
    }

    // MARK: - Choix du moteur

    func testPicksEngineFromURL() {
        let (sut, factory, _) = makeSUT()

        sut.play(url: tsURL, isLive: true)          // .ts → VLC
        XCTAssertEqual(sut.engineKind, .vlc)
        XCTAssertEqual(factory.last.kind, .vlc)
        XCTAssertEqual(factory.last.preparedURL, tsURL)
        XCTAssertEqual(factory.last.playCalled, 1)
        XCTAssertEqual(sut.state, .preparing)

        sut.play(url: mp4URL, isLive: false)        // .mp4 → AVPlayer
        XCTAssertEqual(sut.engineKind, .avPlayer)
        XCTAssertEqual(factory.last.kind, .avPlayer)
    }

    // MARK: - Bascule

    func testBasculeOnUnsupportedFormat() {
        let (sut, factory, _) = makeSUT()
        sut.play(url: tsURL, isLive: true)          // VLC d'abord
        factory.last.emit(.failed(.unsupported))    // conteneur/codec illisible

        XCTAssertEqual(factory.created.count, 2, "doit créer un 2e moteur")
        XCTAssertEqual(sut.engineKind, .avPlayer, "bascule vers l'autre moteur")
        XCTAssertEqual(factory.last.preparedURL?.absoluteString,
                       "http://s/live/u/p/1.m3u8", "URL alternative .ts→.m3u8")
        XCTAssertEqual(sut.state, .preparing)
    }

    func testBasculeHappensOnlyOnce() {
        let (sut, factory, _) = makeSUT()
        sut.play(url: tsURL, isLive: true)
        factory.last.emit(.failed(.unsupported))    // 1re bascule → AVPlayer
        factory.last.emit(.failed(.unsupported))    // le 2e moteur échoue aussi

        XCTAssertEqual(factory.created.count, 2, "pas de 3e moteur (anti ping-pong)")
        XCTAssertEqual(sut.state, .failed(.unsupported))
    }

    // MARK: - Retry réseau

    func testNetworkFailureSchedulesRetryThenRecovers() {
        let (sut, factory, scheduler) = makeSUT()
        sut.play(url: tsURL, isLive: true)
        factory.last.emit(netFail())

        XCTAssertEqual(scheduler.pendingCount, 1, "un retry doit être programmé")
        XCTAssertEqual(factory.created.count, 1, "pas encore relancé avant le délai")

        scheduler.fireNext()                         // le back-off s'écoule
        XCTAssertEqual(factory.created.count, 2, "relance sur le même moteur")
        XCTAssertEqual(factory.last.kind, .vlc)

        factory.last.emit(.playing)                  // lecture stable
        XCTAssertEqual(sut.state, .playing)
    }

    func testRetryExhaustsThenSurfacesError() {
        let (sut, factory, scheduler) = makeSUT()
        sut.play(url: mp4URL, isLive: false)         // VOD : 3 tentatives max

        factory.last.emit(netFail()); scheduler.fireNext()   // 1
        factory.last.emit(netFail()); scheduler.fireNext()   // 2
        factory.last.emit(netFail()); scheduler.fireNext()   // 3
        factory.last.emit(netFail())                         // 4e refusée

        XCTAssertEqual(scheduler.pendingCount, 0)
        XCTAssertEqual(factory.created.count, 4)
        if case .failed(let err) = sut.state {
            XCTAssertEqual(err.kind, .noConnection)
        } else {
            XCTFail("doit remonter l'erreur après épuisement des tentatives")
        }
    }

    func testPermanentErrorSurfacesImmediately() {
        let (sut, factory, scheduler) = makeSUT()
        sut.play(url: tsURL, isLive: true)
        factory.last.emit(.failed(PlaybackError.classify(statusCode: 403)))  // abo expiré

        XCTAssertEqual(scheduler.pendingCount, 0, "aucun retry sur 401/403")
        XCTAssertEqual(factory.created.count, 1, "aucune bascule")
        if case .failed(let err) = sut.state {
            XCTAssertEqual(err.kind, .accessDenied)
        } else {
            XCTFail("doit remonter immédiatement l'accès refusé")
        }
    }

    func testStopCancelsPendingRetry() {
        let (sut, factory, scheduler) = makeSUT()
        sut.play(url: tsURL, isLive: true)
        factory.last.emit(netFail())
        XCTAssertEqual(scheduler.pendingCount, 1)

        sut.stop()
        scheduler.fireNext()                         // le job obsolète doit se désamorcer

        XCTAssertEqual(factory.created.count, 1, "stop invalide le retry en attente")
        XCTAssertEqual(sut.state, .idle)
    }

    // MARK: - Passe-plats

    func testPauseResumeStop() {
        let (sut, factory, _) = makeSUT()
        sut.play(url: mp4URL, isLive: false)
        XCTAssertEqual(factory.last.playCalled, 1)

        sut.pause()
        XCTAssertEqual(sut.state, .paused)

        sut.resume()
        XCTAssertEqual(factory.last.playCalled, 2)

        let engine = factory.last
        sut.stop()
        XCTAssertEqual(engine.stopCalled, 1)
        XCTAssertEqual(sut.state, .idle)
    }
}
