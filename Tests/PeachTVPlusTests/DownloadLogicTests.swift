import XCTest
@testable import PeachTVPlus

final class DownloadLogicTests: XCTestCase {

    private func rec(_ key: String, _ status: DownloadStatus, updatedAt: Double) -> DownloadRecord {
        DownloadRecord(contentKey: key, contentType: "vod", playlistId: "A", title: key,
                       maskedURL: "m", ext: "mp4", localPath: nil, status: status.rawValue,
                       percent: 0, bytesDownloaded: 0, totalBytes: nil, resumeData: nil,
                       errorMessage: nil, updatedAt: updatedAt)
    }

    // MARK: - File d'attente

    func testQueueFillsFreeSlotsFIFO() {
        let policy = DownloadQueuePolicy(maxConcurrent: 3)
        let records = [
            rec("d1", .downloading, updatedAt: 0),
            rec("q30", .queued, updatedAt: 30),
            rec("q10", .queued, updatedAt: 10),
            rec("q20", .queued, updatedAt: 20),
        ]
        // 1 en cours → 2 places → les 2 plus anciens en file.
        XCTAssertEqual(policy.nextToStart(records: records), ["q10", "q20"])
    }

    func testQueueFullStartsNothing() {
        let policy = DownloadQueuePolicy(maxConcurrent: 2)
        let records = [
            rec("d1", .downloading, updatedAt: 0),
            rec("d2", .downloading, updatedAt: 1),
            rec("q1", .queued, updatedAt: 2),
        ]
        XCTAssertTrue(policy.nextToStart(records: records).isEmpty)
    }

    // MARK: - Espace disque

    func testDiskSpaceGuard() {
        let gb: Int64 = 1024 * 1024 * 1024
        XCTAssertTrue(DiskSpaceGuard.canStart(estimatedBytes: 500 * 1024 * 1024, freeBytes: gb))
        XCTAssertFalse(DiskSpaceGuard.canStart(estimatedBytes: 200 * 1024 * 1024,
                                               freeBytes: 400 * 1024 * 1024)) // marge 300 Mo non tenue
    }

    // MARK: - Wi-Fi uniquement

    func testWiFiOnlyPolicy() {
        let onlyWifi = WiFiOnlyPolicy(wifiOnly: true)
        XCTAssertTrue(onlyWifi.allows(.wifi))
        XCTAssertFalse(onlyWifi.allows(.cellular))
        XCTAssertFalse(onlyWifi.allows(.none))

        let allowsCell = WiFiOnlyPolicy(wifiOnly: false)
        XCTAssertTrue(allowsCell.allows(.cellular))
        XCTAssertFalse(allowsCell.allows(.none))
    }

    // MARK: - Erreurs

    func testDownloadErrorDiskFullTakesPrecedence() {
        let e = DownloadError.classify(statusCode: 401, isDiskFull: true)
        XCTAssertEqual(e.kind, .insufficientStorage)
        XCTAssertFalse(e.allowsRetry)
    }

    func testDownloadErrorSubscriptionExpiredNoRetry() {
        for code in [401, 403] {
            let e = DownloadError.classify(statusCode: code)
            XCTAssertEqual(e.kind, .subscriptionExpired)
            XCTAssertFalse(e.allowsRetry)
        }
    }

    func testDownloadErrorNetworkIsRetryable() {
        XCTAssertTrue(DownloadError.classify(urlErrorCode: .notConnectedToInternet).allowsRetry)
        XCTAssertEqual(DownloadError.classify(urlErrorCode: .cannotFindHost).kind, .serverUnreachable)
    }

    // MARK: - Bouton 6 états

    func testButtonStateMapping() {
        XCTAssertEqual(DownloadButtonState.from(nil), .notDownloaded)
        let ui = { (s: DownloadStatus, p: Double) in
            DownloadUiState(contentKey: "k", title: "t", status: s, percent: p)
        }
        XCTAssertEqual(DownloadButtonState.from(ui(.queued, 0)), .queued)
        XCTAssertEqual(DownloadButtonState.from(ui(.downloading, 0.5)), .inProgress(0.5))
        XCTAssertEqual(DownloadButtonState.from(ui(.paused, 0.3)), .paused(0.3))
        XCTAssertEqual(DownloadButtonState.from(ui(.completed, 1)), .completed)
        XCTAssertEqual(DownloadButtonState.from(ui(.failed, 0)), .failed)
    }

    func testButtonAccessibilityLabel() {
        XCTAssertEqual(DownloadButtonState.inProgress(0.5).accessibilityLabel, "Téléchargement 50 %")
        XCTAssertEqual(DownloadButtonState.completed.accessibilityLabel, "Disponible hors ligne")
    }

    // MARK: - Chemins locaux (anti path-traversal)

    func testSanitizedExtensionAllowlist() {
        XCTAssertEqual(DownloadPaths.sanitizedExtension("MKV"), "mkv")
        XCTAssertEqual(DownloadPaths.sanitizedExtension("ts"), "ts")
        XCTAssertEqual(DownloadPaths.sanitizedExtension("exe"), "mp4")   // repli
        XCTAssertEqual(DownloadPaths.sanitizedExtension("../../etc"), "mp4")
    }

    func testSafeFileNameHasNoPathSeparator() {
        let name = DownloadPaths.safeFileName(for: "movie:../../evil", ext: "exe")
        XCTAssertFalse(name.contains("/"))
        XCTAssertTrue(name.hasSuffix(".mp4"))
    }

    func testLocalURLStaysUnderDownloads() throws {
        let url = try DownloadPaths.localURL(for: "movie:1", ext: "ts")
        XCTAssertTrue(url.path.contains("/Downloads/"))
        XCTAssertEqual(url.pathExtension, "ts")
    }
}
