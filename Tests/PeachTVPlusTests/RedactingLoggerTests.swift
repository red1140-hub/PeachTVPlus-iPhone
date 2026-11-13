import XCTest
@testable import PeachTVPlus

final class RedactingLoggerTests: XCTestCase {

    func testRedactsQueryCredentials() {
        let input = "http://s.com/player_api.php?username=bob&password=pw123&action=get_live_streams"
        let out = RedactingLogger.redact(input)
        XCTAssertFalse(out.contains("bob"))
        XCTAssertFalse(out.contains("pw123"))
        XCTAssertTrue(out.contains("username=***"))
        XCTAssertTrue(out.contains("password=***"))
        XCTAssertTrue(out.contains("action=get_live_streams"))
    }

    func testRedactsLivePathCredentials() {
        let out = RedactingLogger.redact("http://s.com/live/bob/pw123/1.ts")
        XCTAssertEqual(out, "http://s.com/live/***/***/1.ts")
    }

    func testRedactsTimeshiftPathCredentials() {
        // Cas qui régressait côté Android (regex timeshift manquante) — couvert ici d'emblée.
        let out = RedactingLogger.redact("http://s.com/timeshift/bob/pw123/60/1970-01-01:00-00/5.ts")
        XCTAssertFalse(out.contains("bob"))
        XCTAssertFalse(out.contains("pw123"))
        XCTAssertTrue(out.contains("/timeshift/***/***/"))
    }

    func testLeavesCleanStringUntouched() {
        let clean = "http://s.com/player_api.php?action=get_vod_categories"
        XCTAssertEqual(RedactingLogger.redact(clean), clean)
    }
}
