import XCTest
@testable import PeachTVPlus

final class PlayerLogicTests: XCTestCase {

    // MARK: - StreamFormat

    func testPreferredEngineByFormat() {
        XCTAssertEqual(StreamFormat.preferredEngine(for: URL(string: "http://s/live/u/p/1.m3u8")!), .avPlayer)
        XCTAssertEqual(StreamFormat.preferredEngine(for: URL(string: "http://s/live/u/p/1.ts")!), .vlc)
        XCTAssertEqual(StreamFormat.preferredEngine(for: URL(string: "http://s/live/u/p/1")!), .vlc)   // sans extension
        XCTAssertEqual(StreamFormat.preferredEngine(for: URL(string: "http://s/movie/u/p/1.mp4")!), .avPlayer)
        XCTAssertEqual(StreamFormat.preferredEngine(for: URL(string: "http://s/movie/u/p/1.mkv")!), .vlc)
    }

    func testAlternateURLSwapsTsAndHls() {
        XCTAssertEqual(StreamFormat.alternateURL(for: URL(string: "http://s/live/u/p/1.ts")!)?.absoluteString,
                       "http://s/live/u/p/1.m3u8")
        XCTAssertEqual(StreamFormat.alternateURL(for: URL(string: "http://s/live/u/p/1.m3u8")!)?.absoluteString,
                       "http://s/live/u/p/1.ts")
        XCTAssertNil(StreamFormat.alternateURL(for: URL(string: "http://s/movie/u/p/1.mp4")!))
    }

    func testFallbackSwitchesEngineAndUrl() {
        let ts = URL(string: "http://s/live/u/p/1.ts")!
        let fb = StreamFormat.fallback(for: ts, from: .vlc)
        XCTAssertEqual(fb.kind, .avPlayer)
        XCTAssertEqual(fb.url.absoluteString, "http://s/live/u/p/1.m3u8")

        // Sans URL alternative : on bascule de moteur en gardant l'URL.
        let mp4 = URL(string: "http://s/movie/u/p/1.mp4")!
        let fb2 = StreamFormat.fallback(for: mp4, from: .avPlayer)
        XCTAssertEqual(fb2.kind, .vlc)
        XCTAssertEqual(fb2.url, mp4)
    }

    func testFallbackGuardAllowsOneSwitch() {
        var guardState = PlaybackFallbackGuard()
        let url = URL(string: "http://s/live/u/p/1.ts")!
        XCTAssertNotNil(guardState.switchTarget(for: url, from: .vlc))
        XCTAssertNil(guardState.switchTarget(for: url, from: .avPlayer))  // 2e bascule refusée
        guardState.reset()
        XCTAssertNotNil(guardState.switchTarget(for: url, from: .vlc))    // réarmé
    }

    // MARK: - BufferProfile

    func testBufferProfileValues() {
        XCTAssertEqual(BufferProfile.default, .balanced)
        XCTAssertEqual(BufferProfile.lowLatency.forwardBufferSeconds(isLive: true), 2)
        XCTAssertFalse(BufferProfile.lowLatency.waitsToMinimizeStalling)
        XCTAssertEqual(BufferProfile.balanced.forwardBufferSeconds(isLive: true), 5)
        XCTAssertEqual(BufferProfile.balanced.forwardBufferSeconds(isLive: false), 8)
        XCTAssertTrue(BufferProfile.balanced.waitsToMinimizeStalling)
        XCTAssertEqual(BufferProfile.antiStutter.forwardBufferSeconds(isLive: false), 30)
        XCTAssertEqual(BufferProfile.antiStutter.vlcNetworkCachingMs, 8000)
    }

    // MARK: - PlaybackRetryPolicy

    func testRetryDelaysBackOffCapped() {
        let p = PlaybackRetryPolicy()
        XCTAssertEqual(p.delay(forAttempt: 1), 1)
        XCTAssertEqual(p.delay(forAttempt: 2), 2)
        XCTAssertEqual(p.delay(forAttempt: 3), 4)
        XCTAssertEqual(p.delay(forAttempt: 4), 8)
        XCTAssertEqual(p.delay(forAttempt: 5), 8)   // plafond
    }

    func testRetryNoRetryOnPermanentCodes() {
        let p = PlaybackRetryPolicy()
        for code in [401, 403, 404] {
            XCTAssertTrue(p.isPermanent(statusCode: code))
            XCTAssertFalse(p.shouldRetry(statusCode: code, attempt: 1, isLive: true))
        }
        XCTAssertFalse(p.isPermanent(statusCode: 500))
        XCTAssertTrue(p.shouldRetry(statusCode: 500, attempt: 1, isLive: true))
    }

    func testRetryMoreAttemptsLiveThanVOD() {
        let p = PlaybackRetryPolicy()
        XCTAssertTrue(p.shouldRetry(statusCode: nil, attempt: 6, isLive: true))
        XCTAssertFalse(p.shouldRetry(statusCode: nil, attempt: 7, isLive: true))
        XCTAssertTrue(p.shouldRetry(statusCode: nil, attempt: 3, isLive: false))
        XCTAssertFalse(p.shouldRetry(statusCode: nil, attempt: 4, isLive: false))
    }

    func testRetryControllerCountsAndResets() {
        let c = PlaybackRetryController(isLive: true)
        XCTAssertEqual(c.registerFailure(statusCode: nil), 1)
        XCTAssertEqual(c.registerFailure(statusCode: nil), 2)
        XCTAssertEqual(c.registerFailure(statusCode: nil), 4)
        XCTAssertEqual(c.attempt, 3)
        c.reset()
        XCTAssertEqual(c.attempt, 0)
        XCTAssertEqual(c.registerFailure(statusCode: nil), 1)
    }

    func testRetryControllerStopsOnPermanent() {
        let c = PlaybackRetryController(isLive: true)
        XCTAssertNil(c.registerFailure(statusCode: 401))   // abandon immédiat
        XCTAssertEqual(c.attempt, 0)
    }

    func testRetryControllerExhaustsVOD() {
        let c = PlaybackRetryController(isLive: false)
        XCTAssertNotNil(c.registerFailure(statusCode: nil))  // 1
        XCTAssertNotNil(c.registerFailure(statusCode: nil))  // 2
        XCTAssertNotNil(c.registerFailure(statusCode: nil))  // 3
        XCTAssertNil(c.registerFailure(statusCode: nil))     // 4e refusée (max VOD = 3)
    }

    // MARK: - PlaybackError.classify

    func testErrorClassificationStatusCodes() {
        XCTAssertEqual(PlaybackError.classify(statusCode: 404).kind, .streamUnavailable)
        XCTAssertEqual(PlaybackError.classify(statusCode: 401).kind, .accessDenied)
        XCTAssertEqual(PlaybackError.classify(statusCode: 403).kind, .accessDenied)
    }

    func testErrorClassificationURLErrors() {
        XCTAssertEqual(PlaybackError.classify(urlErrorCode: .notConnectedToInternet).kind, .noConnection)
        XCTAssertEqual(PlaybackError.classify(urlErrorCode: .cannotFindHost).kind, .serverUnreachable)
        XCTAssertEqual(PlaybackError.classify(urlErrorCode: .timedOut).kind, .serverSlow)
        XCTAssertEqual(PlaybackError.classify(urlErrorCode: .appTransportSecurityRequiresSecureConnection).kind,
                       .cleartextBlocked)
    }

    func testErrorStatusCodeTakesPrecedenceOverURLError() {
        // Un 404 reste un 404 même si la session a aussi vu un timeout.
        XCTAssertEqual(PlaybackError.classify(statusCode: 404, urlErrorCode: .timedOut).kind, .streamUnavailable)
    }

    func testBehindLiveIsSilent() {
        XCTAssertTrue(PlaybackError.behindLive.isSilent)
    }

    // MARK: - PlayerGestureArbiter

    func testGestureTapTogglesControls() {
        let arbiter = PlayerGestureArbiter(isLive: true)
        XCTAssertEqual(arbiter.resolve(.tap), .toggleControls)
    }

    func testVerticalDragVolumeAndBrightness() {
        let arbiter = PlayerGestureArbiter(isLive: false)
        XCTAssertEqual(arbiter.resolve(.verticalDrag(side: .right, delta: 0.5)), .adjustVolume(0.5))
        XCTAssertEqual(arbiter.resolve(.verticalDrag(side: .left, delta: -0.2)), .adjustBrightness(-0.2))
    }

    func testHorizontalDragChangesChannelOnlyLiveAboveThreshold() {
        let live = PlayerGestureArbiter(isLive: true)
        XCTAssertEqual(live.resolve(.horizontalDrag(delta: 0.5)), .changeChannel(1))
        XCTAssertEqual(live.resolve(.horizontalDrag(delta: -0.5)), .changeChannel(-1))
        XCTAssertEqual(live.resolve(.horizontalDrag(delta: 0.1)), .none)   // sous le seuil

        let vod = PlayerGestureArbiter(isLive: false)
        XCTAssertEqual(vod.resolve(.horizontalDrag(delta: 0.9)), .none)    // pas de chaîne en VOD
    }
}
