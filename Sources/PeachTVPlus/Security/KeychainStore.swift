import Foundation
import Security

/// Erreurs Keychain. On distingue une **absence** (légitime), un échec **transitoire**
/// (appareil verrouillé…) et une corruption **permanente** — cette distinction pilote la
/// migration non destructive (ne jamais effacer un secret sur un raté transitoire).
enum KeychainError: Error, Equatable {
    case unexpectedStatus(OSStatus)   // transitoire OU permanent selon le code
    case decodingFailed               // blob présent mais corrompu / illisible
    case notFound
}

/// Accès centralisé au trousseau (équivalent du `SecureSessionStore` Android — Tink).
/// Classe de protection : **`AfterFirstUnlockThisDeviceOnly`**, **jamais** synchronisé iCloud
/// (`kSecAttrSynchronizable = false`). `Security.framework` seul, aucune dépendance tierce.
/// Voir `docs/security.md §1`.
struct KeychainStore {

    private let service: String

    init(service: String = "com.peachtvplus.app.credentials") {
        self.service = service
    }

    /// Écrit (ou remplace) un blob opaque sous `account`.
    func set(_ data: Data, account: String) throws {
        // SecItemAdd échoue sur doublon (errSecDuplicateItem) → on supprime d'abord.
        SecItemDelete(baseQuery(account) as CFDictionary)

        var attrs = baseQuery(account)
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        attrs[kSecAttrSynchronizable as String] = kCFBooleanFalse   // JAMAIS iCloud

        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    /// Lit le blob, ou `nil` si **absent**. Distingue « absent » (1er lancement) d'« erreur »
    /// (verrou, etc.) : ne jamais interpréter un échec comme « vide » (cf. migration §2.3).
    func get(account: String) throws -> Data? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { throw KeychainError.decodingFailed }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func remove(account: String) throws {
        let status = SecItemDelete(baseQuery(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse,   // cohérent lecture/écriture
        ]
    }
}
