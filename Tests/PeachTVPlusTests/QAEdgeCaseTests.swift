import XCTest
@testable import PeachTVPlus

/// Durcissement M6 : formatage de durée, cas **adversariaux** de réinjection d'identifiants
/// (sécurité), et libellés d'accessibilité du bouton de téléchargement. Pur, sans appareil.
final class QAEdgeCaseTests: XCTestCase {

    // MARK: - TimeFormatting

    func testClockFormatting() {
        XCTAssertEqual(TimeFormatting.clock(0), "00:00")
        XCTAssertEqual(TimeFormatting.clock(5), "00:05")
        XCTAssertEqual(TimeFormatting.clock(65), "01:05")
        XCTAssertEqual(TimeFormatting.clock(3661), "1:01:01")
        XCTAssertEqual(TimeFormatting.clock(-1), "--:--")
        XCTAssertEqual(TimeFormatting.clock(.nan), "--:--")
        XCTAssertEqual(TimeFormatting.clock(.infinity), "--:--")
    }

    // MARK: - Réinjection d'identifiants (anti-fuite)

    private let creds = XtreamCredentials(serverUrl: "http://s.com", username: "bob", password: "pw")

    func testReinjectRefusedWhenNoMarker() {
        // URL déjà réelle (aucun marqueur) → on ne réinjecte pas.
        let real = "http://s.com/movie/bob/pw/7.mp4"
        XCTAssertNil(XtreamURLFactory.reinjectCredentials(into: real, credentials: creds))
    }

    func testReinjectRefusedWhenNoStreamKind() {
        // Chemin sans segment live/movie/series/timeshift → refus.
        let weird = "http://s.com/foo/__cred__/__cred__/7.mp4"
        XCTAssertNil(XtreamURLFactory.reinjectCredentials(into: weird, credentials: creds))
    }

    func testReinjectRestoresOnValidMaskedTimeshift() {
        let masked = "http://s.com/timeshift/__cred__/__cred__/60/2024-01-01:00-00/5.ts"
        let s = XtreamURLFactory.reinjectCredentials(into: masked, credentials: creds)?.absoluteString
        XCTAssertNotNil(s)
        XCTAssertTrue(s?.contains("/timeshift/bob/pw/60/") == true)
        XCTAssertTrue(s?.contains("5.ts") == true)
        XCTAssertFalse(s?.contains("__cred__") == true)
        // Le « : » du horodatage peut rester littéral ou être percent-encodé selon Foundation.
        XCTAssertTrue(s?.contains("2024-01-01:00-00") == true || s?.contains("2024-01-01%3A00-00") == true)
    }

    // MARK: - Accessibilité du bouton de téléchargement

    func testDownloadButtonStateMapping() {
        XCTAssertEqual(DownloadButtonState.from(nil), .notDownloaded)
        let dl = DownloadUiState(contentKey: "movie:1", title: "F", status: .downloading, percent: 0.4)
        XCTAssertEqual(DownloadButtonState.from(dl), .inProgress(0.4))
        let done = DownloadUiState(contentKey: "movie:1", title: "F", status: .completed, percent: 1)
        XCTAssertEqual(DownloadButtonState.from(done), .completed)
    }

    func testDownloadButtonAccessibilityLabels() {
        XCTAssertEqual(DownloadButtonState.notDownloaded.accessibilityLabel, "Télécharger")
        XCTAssertEqual(DownloadButtonState.completed.accessibilityLabel, "Disponible hors ligne")
        XCTAssertEqual(DownloadButtonState.inProgress(0.5).accessibilityLabel, "Téléchargement 50 %")
        XCTAssertEqual(DownloadButtonState.paused(0.25).accessibilityLabel, "En pause 25 %")
    }
}
