import XCTest
@testable import PeachTVPlus

final class EpgCatchUpTests: XCTestCase {

    private func prog(_ id: String, start: TimeInterval, end: TimeInterval, archive: Bool = false) -> EpgProgramme {
        EpgProgramme(id: id, title: "T\(id)", description: "",
                     start: Date(timeIntervalSince1970: start),
                     end: Date(timeIntervalSince1970: end),
                     hasArchive: archive)
    }

    // MARK: - EpgTimeline

    func testCurrentAndNext() {
        let timeline = EpgTimeline([
            prog("1", start: 0, end: 100),
            prog("2", start: 100, end: 200),
            prog("3", start: 200, end: 300),
        ])
        let at = Date(timeIntervalSince1970: 150)
        XCTAssertEqual(timeline.current(at: at)?.id, "2")
        XCTAssertEqual(timeline.next(at: at)?.id, "3")
    }

    func testCurrentNilInGap() {
        let timeline = EpgTimeline([prog("1", start: 0, end: 100)])
        XCTAssertNil(timeline.current(at: Date(timeIntervalSince1970: 150)))
    }

    func testProgressHalfway() {
        let timeline = EpgTimeline([prog("1", start: 0, end: 100)])
        let p = timeline.programmes[0]
        XCTAssertEqual(timeline.progress(of: p, at: Date(timeIntervalSince1970: 50)), 0.5)
        XCTAssertEqual(timeline.progress(of: p, at: Date(timeIntervalSince1970: 0)), 0)
        XCTAssertEqual(timeline.progress(of: p, at: Date(timeIntervalSince1970: 999)), 1)   // borné
    }

    func testTimelineSortsByStart() {
        let timeline = EpgTimeline([
            prog("late", start: 200, end: 300),
            prog("early", start: 0, end: 100),
        ])
        XCTAssertEqual(timeline.programmes.map(\.id), ["early", "late"])
    }

    // MARK: - CatchUp

    func testTimeshiftURLFromArchivedProgramme() {
        let creds = XtreamCredentials(serverUrl: "http://s.com", username: "u", password: "p")
        let factory = XtreamURLFactory(credentials: creds)
        let utc = TimeZone(identifier: "UTC")!
        // 1970-01-01 00:00 → 01:00 UTC : durée 60 min.
        let programme = prog("5", start: 0, end: 3600, archive: true)

        let url = CatchUp.timeshiftURL(for: programme, streamId: "5", using: factory, timeZone: utc)
        XCTAssertEqual(url?.absoluteString, "http://s.com/timeshift/u/p/60/1970-01-01:00-00/5.ts")
    }

    func testNoTimeshiftWithoutArchive() {
        let factory = XtreamURLFactory(credentials:
            XtreamCredentials(serverUrl: "http://s.com", username: "u", password: "p"))
        let programme = prog("5", start: 0, end: 3600, archive: false)
        XCTAssertNil(CatchUp.timeshiftURL(for: programme, streamId: "5", using: factory))
    }

    func testNoTimeshiftWithZeroDuration() {
        let factory = XtreamURLFactory(credentials:
            XtreamCredentials(serverUrl: "http://s.com", username: "u", password: "p"))
        let programme = prog("5", start: 100, end: 100, archive: true)   // durée nulle
        XCTAssertNil(CatchUp.timeshiftURL(for: programme, streamId: "5", using: factory))
    }
}
