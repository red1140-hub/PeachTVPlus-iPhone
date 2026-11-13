import Foundation
import os

/// Journalisation qui **masque systématiquement** les secrets avant toute sortie.
///
/// Masque les paramètres `username=`/`password=` d'une query ET les segments
/// identifiants d'une URL de flux (`/live/{user}/{pass}/`, idem `movie`/`series`/
/// `timeshift`). **Aucune URL brute ne doit jamais atteindre un logger** — une règle
/// CI `grep` fait échouer la build si un `print(...)` contient une URL/secret
/// (voir `.github/workflows/ci.yml`).
enum RedactingLogger {
    private static let logger = Logger(subsystem: "com.peachtvplus.app", category: "net")

    /// Remplace tout secret par `***` dans une chaîne arbitraire (query + path).
    static func redact(_ input: String) -> String {
        var out = input

        // 1) Paramètres de query : username=… / password=… (jusqu'au prochain & ou fin).
        out = replace(in: out, pattern: "(?i)(username=)[^&\\s]+", template: "$1***")
        out = replace(in: out, pattern: "(?i)(password=)[^&\\s]+", template: "$1***")

        // 2) Segments de path : /live|movie|series|timeshift/USER/PASS/ → masque USER et PASS.
        out = replace(
            in: out,
            pattern: "(?i)(/(?:live|movie|series|timeshift)/)[^/\\s]+/[^/\\s]+/",
            template: "$1***/***/"
        )
        return out
    }

    static func debug(_ message: @autoclosure () -> String) {
        #if DEBUG
        logger.debug("\(redact(message()), privacy: .public)")
        #endif
    }

    static func error(_ message: @autoclosure () -> String) {
        logger.error("\(redact(message()), privacy: .public)")
    }

    private static func replace(in input: String, pattern: String, template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return input }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        return regex.stringByReplacingMatches(in: input, range: range, withTemplate: template)
    }
}
