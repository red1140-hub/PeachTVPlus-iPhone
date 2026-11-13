import XCTest
@testable import PeachTVPlus

final class DownloadStoreTests: XCTestCase {

    private func makeStore() throws -> DownloadStore { try AppDatabase.inMemoryDownloadStore() }

    private func record(_ key: String, status: DownloadStatus, updatedAt: Double,
                        playlistId: String = "A") -> DownloadRecord {
        DownloadRecord(contentKey: key, contentType: "vod", playlistId: playlistId,
                       title: "T\(key)", maskedURL: "http://s.com/movie/__cred__/__cred__/\(key).mp4",
                       ext: "mp4", localPath: nil, status: status.rawValue, percent: 0,
                       bytesDownloaded: 0, totalBytes: nil, resumeData: nil, errorMessage: nil,
                       updatedAt: updatedAt)
    }

    func testUpsertAndFetch() throws {
        let store = try makeStore()
        try store.upsert(record("movie:1", status: .queued, updatedAt: 1))
        XCTAssertEqual(try store.record(contentKey: "movie:1")?.downloadStatus, .queued)
        XCTAssertNil(try store.record(contentKey: "movie:x"))
    }

    func testActiveFiltersAndOrders() throws {
        let store = try makeStore()
        try store.upsert(record("movie:q", status: .queued, updatedAt: 2))
        try store.upsert(record("movie:d", status: .downloading, updatedAt: 1))
        try store.upsert(record("movie:p", status: .paused, updatedAt: 3))
        try store.upsert(record("movie:c", status: .completed, updatedAt: 4))
        try store.upsert(record("movie:f", status: .failed, updatedAt: 5))

        XCTAssertEqual(try store.active().map(\.contentKey), ["movie:d", "movie:q", "movie:p"])
        XCTAssertEqual(try store.completed().map(\.contentKey), ["movie:c"])
    }

    func testTargetedMutations() throws {
        let store = try makeStore()
        try store.upsert(record("movie:1", status: .queued, updatedAt: 1))

        try store.setStatus(contentKey: "movie:1", .downloading)
        XCTAssertEqual(try store.record(contentKey: "movie:1")?.downloadStatus, .downloading)

        try store.setProgress(contentKey: "movie:1", percent: 0.4, bytes: 400, total: 1000)
        let afterProgress = try store.record(contentKey: "movie:1")
        XCTAssertEqual(afterProgress?.percent, 0.4)
        XCTAssertEqual(afterProgress?.bytesDownloaded, 400)
        XCTAssertEqual(afterProgress?.totalBytes, 1000)

        try store.setResumeData(contentKey: "movie:1", Data([1, 2, 3]))
        XCTAssertEqual(try store.record(contentKey: "movie:1")?.resumeData, Data([1, 2, 3]))

        try store.setLocalPath(contentKey: "movie:1", "/tmp/x.mp4")
        XCTAssertEqual(try store.record(contentKey: "movie:1")?.localPath, "/tmp/x.mp4")

        try store.setStatus(contentKey: "movie:1", .failed, error: "boom")
        XCTAssertEqual(try store.record(contentKey: "movie:1")?.errorMessage, "boom")
    }

    func testPurgePlaylistAndClearAll() throws {
        let store = try makeStore()
        try store.upsert(record("movie:1", status: .completed, updatedAt: 1, playlistId: "A"))
        try store.upsert(record("movie:2", status: .completed, updatedAt: 2, playlistId: "B"))

        try store.purgePlaylist("A")
        XCTAssertNil(try store.record(contentKey: "movie:1"))
        XCTAssertNotNil(try store.record(contentKey: "movie:2"))

        try store.clearAll()
        XCTAssertTrue(try store.all().isEmpty)
    }
}
