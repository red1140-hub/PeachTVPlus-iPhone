import Foundation

/// Décodeur tolérant pour les panels Xtream : une même clé (`stream_id`,
/// `category_id`, timestamps EPG…) arrive tantôt en `Int`, `Double`, `Bool`,
/// `String`, ou absente selon le fournisseur. `FlexibleString` absorbe tout ça
/// et expose toujours une `String` (vide si absent/null). **Non négociable** —
/// c'est la principale source de crash d'un client Xtream naïf.
struct FlexibleString: Codable, Equatable, Hashable, ExpressibleByStringLiteral {
    let value: String

    init(_ value: String) { self.value = value }
    init(stringLiteral value: String) { self.value = value }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { value = ""; return }
        if let s = try? c.decode(String.self) { value = s; return }
        if let i = try? c.decode(Int.self) { value = String(i); return }
        if let d = try? c.decode(Double.self) {
            // Évite le « .0 » parasite quand le double est en fait un entier.
            if d.rounded() == d && abs(d) < 1e15 {
                value = String(Int64(d))
            } else {
                value = String(d)
            }
            return
        }
        if let b = try? c.decode(Bool.self) { value = b ? "1" : "0"; return }
        value = ""
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(value)
    }

    var isEmpty: Bool { value.isEmpty }
    var intValue: Int? { Int(value) }
    var doubleValue: Double? { Double(value) }
    /// Timestamp epoch (secondes) → `Date`, si parseable.
    var epochDate: Date? { doubleValue.map { Date(timeIntervalSince1970: $0) } }
}
