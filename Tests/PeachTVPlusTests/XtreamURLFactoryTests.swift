import XCTest
@testable import PeachTVPlus

final class XtreamURLFactoryTests: XCTestCase {

    private let creds = XtreamCredentials(serverUrl: "http://s.com", username: "bob", password: "pw123")
    private var factory: XtreamURLFactory { XtreamURLFactory(credentials: creds) }

    func testAuthURLCarriesCredentials() {
        let s = factory.auth().absoluteString
        XCTAssertTrue(s.contains("/player_api.php"))
        XCTAssertTrue(s.contains("username=bob"))
        XCTAssertTrue(s.contains("password=pw123"))
    }

    func testActionWithCategory() {
        let s = factory.action("get_live_streams", categoryId: "42").absoluteString
        XCTAssertTrue(s.contains("action=get_live_streams"))
        XCTAssertTrue(s.contains("category_id=42"))
    }

    func testLiveStreamPath() {
        XCTAssertEqual(factory.liveStreamURL(id: "1").absoluteString, "http://s.com/live/bob/pw123/1.ts")
    }

    func testMovieStreamPathWithExtension() {
        XCTAssertEqual(factory.movieURL(id: "7", ext: "mp4").absoluteString, "http://s.com/movie/bob/pw123/7.mp4")
    }

    func testMaskedURLHasNoCredentials() {
        let masked = factory.maskedStreamURLString(kind: .movie, id: "7", ext: "mp4")
        XCTAssertEqual(masked, "http://s.com/movie/__cred__/__cred__/7.mp4")
        XCTAssertFalse(masked.contains("bob"))
        XCTAssertFalse(masked.contains("pw123"))
    }

    func testReinjectRestoresCredentialsWhenHostMatches() {
        let masked = factory.maskedStreamURLString(kind: .movie, id: "7", ext: "mp4")
        let url = XtreamURLFactory.reinjectCredentials(into: masked, credentials: creds)
        XCTAssertEqual(url?.absoluteString, "http://s.com/movie/bob/pw123/7.mp4")
    }

    func testReinjectRefusedWhenHostDiffers() {
        let masked = factory.maskedStreamURLString(kind: .movie, id: "7", ext: "mp4")
        let other = XtreamCredentials(serverUrl: "http://other.com", username: "bob", password: "pw123")
        XCTAssertNil(XtreamURLFactory.reinjectCredentials(into: masked, credentials: other))
    }

    func testReinjectRefusedWhenPortDiffers() {
        let masked = factory.maskedStreamURLString(kind: .live, id: "1", ext: "ts")
        let other = XtreamCredentials(serverUrl: "http://s.com:8080", username: "bob", password: "pw123")
        XCTAssertNil(XtreamURLFactory.reinjectCredentials(into: masked, credentials: other))
    }

    func testTimeshiftFormatsStartInGivenTimeZone() {
        let gmt = TimeZone(secondsFromGMT: 0)!
        let s = factory.timeshiftURL(streamId: "5", durationMinutes: 60,
                                     start: Date(timeIntervalSince1970: 0), timeZone: gmt).absoluteString
        XCTAssertTrue(s.contains("/timeshift/bob/pw123/60/"))
        XCTAssertTrue(s.contains("5.ts"))
        // Le « : » du format peut être laissé tel quel ou percent-encodé selon Foundation.
        XCTAssertTrue(s.contains("1970-01-01:00-00") || s.contains("1970-01-01%3A00-00"))
    }
}
