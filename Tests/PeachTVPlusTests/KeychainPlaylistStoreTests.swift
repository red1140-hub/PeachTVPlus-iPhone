import XCTest
@testable import PeachTVPlus

/// Round-trip du store multi-listes chiffré (Keychain). Service **unique par test** pour
/// l'isolation ; nettoyage en `tearDown`. (Le Keychain fonctionne sur simulateur iOS en CI.)
final class KeychainPlaylistStoreTests: XCTestCase {

    private var store: KeychainPlaylistStore!

    override func setUp() {
        super.setUp()
        store = KeychainPlaylistStore(keychain: KeychainStore(service: "test.\(UUID().uuidString)"))
    }

    override func tearDown() {
        store.clear()
        store = nil
        super.tearDown()
    }

    private func cred(_ host: String) -> XtreamCredentials {
        XtreamCredentials(serverUrl: "http://\(host)", username: "u", password: "p")
    }

    func testEmptyWhenNothingStored() {
        XCTAssertEqual(store.load(), .empty)
    }

    func testSaveThenLoadRoundTrip() {
        let a = Playlist(credentials: cred("a.com"))
        let b = Playlist(credentials: cred("b.com"))
        let state = PlaylistState(activeId: b.id, items: [a, b])

        store.save(state)
        let reloaded = store.load()

        XCTAssertEqual(reloaded.items.map(\.id), [a.id, b.id])
        XCTAssertEqual(reloaded.activeId, b.id)
        XCTAssertEqual(reloaded.active?.credentials, b.credentials) // mot de passe bien restauré
    }

    func testClearRemovesBlob() {
        store.save(PlaylistState(activeId: nil, items: [Playlist(credentials: cred("a.com"))]))
        XCTAssertFalse(store.load().items.isEmpty)
        store.clear()
        XCTAssertEqual(store.load(), .empty)
    }

    func testStaleActiveIdFallsBackToFirst() {
        let a = Playlist(credentials: cred("a.com"))
        // activeId ne désigne aucune liste présente → à la relecture, repli sur la première.
        store.save(PlaylistState(activeId: "id-fantome", items: [a]))
        XCTAssertEqual(store.load().activeId, a.id)
    }
}
