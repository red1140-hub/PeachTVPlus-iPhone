import Foundation

/// Formatage d'une durée de lecture en horloge (`mm:ss` ou `h:mm:ss`). Pur et testable ;
/// renvoie `--:--` pour une valeur indisponible (négative, infinie, NaN).
enum TimeFormatting {
    static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }
}
