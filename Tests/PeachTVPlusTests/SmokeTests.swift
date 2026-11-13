import XCTest
@testable import PeachTVPlus

/// Test fumée M0 : garantit que la cible de test se compile et tourne en CI.
/// Les vrais tests unitaires (FlexibleString, XtreamCredentials, URLFactory,
/// redaction, file de téléchargement…) arrivent avec leurs jalons — voir
/// docs/PORT-SPEC.md §9.
final class SmokeTests: XCTestCase {
    func testScaffoldCompilesAndRuns() {
        XCTAssertTrue(true, "Le scaffold M0 se compile et le harnais de test tourne.")
    }
}
