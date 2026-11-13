import Foundation

/// Politique **applicative** de retry (iOS n'a pas de `LoadErrorHandlingPolicy` ExoPlayer).
/// Back-off exponentiel plafonné 1→2→4→8 s, plus de tentatives en Live qu'en VOD, **aucun**
/// retry sur 401/403/404 (abo expiré / flux retiré / URL morte). Pure, testable. Voir
/// `docs/reliability-and-qa.md §1.3`.
struct PlaybackRetryPolicy: Equatable {
    var maxAttemptsLive = 6
    var maxAttemptsVOD = 3
    var capSeconds: TimeInterval = 8

    /// Codes HTTP **permanents** : remonter l'erreur immédiatement, ne jamais boucler.
    static let permanentStatusCodes: Set<Int> = [401, 403, 404]

    func isPermanent(statusCode: Int?) -> Bool {
        guard let code = statusCode else { return false }
        return Self.permanentStatusCodes.contains(code)
    }

    /// Délai avant la tentative n° `attempt` (1-indexé) : 1, 2, 4, 8, 8, 8…
    func delay(forAttempt attempt: Int) -> TimeInterval {
        guard attempt >= 1 else { return 0 }
        let raw = pow(2.0, Double(attempt - 1))
        return min(raw, capSeconds)
    }

    /// Faut-il retenter ? `attempt` = numéro de la tentative envisagée (1 = 1re relance).
    func shouldRetry(statusCode: Int?, attempt: Int, isLive: Bool) -> Bool {
        if isPermanent(statusCode: statusCode) { return false }
        return attempt <= (isLive ? maxAttemptsLive : maxAttemptsVOD)
    }
}

/// Compteur de tentatives + remise à zéro dès lecture stable. Détient l'état que la politique
/// (pure) n'a pas. Remis à zéro au passage `playing` (`AVPlayer.timeControlStatus == .playing`).
final class PlaybackRetryController {
    private let policy: PlaybackRetryPolicy
    private let isLive: Bool
    private(set) var attempt = 0

    init(policy: PlaybackRetryPolicy = .init(), isLive: Bool) {
        self.policy = policy
        self.isLive = isLive
    }

    /// Enregistre un échec et renvoie le délai avant relance, ou `nil` s'il faut abandonner
    /// (code permanent, ou tentatives épuisées) → remonter une erreur claire.
    func registerFailure(statusCode: Int?) -> TimeInterval? {
        let next = attempt + 1
        guard policy.shouldRetry(statusCode: statusCode, attempt: next, isLive: isLive) else {
            return nil
        }
        attempt = next
        return policy.delay(forAttempt: next)
    }

    /// Lecture stable → on oublie l'historique d'échecs (ne pas abandonner après 2 h).
    func reset() { attempt = 0 }
}
