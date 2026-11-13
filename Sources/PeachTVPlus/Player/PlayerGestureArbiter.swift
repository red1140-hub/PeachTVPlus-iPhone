import Foundation

/// **Un seul** gestionnaire de gestes (leçon Android : empiler plusieurs reconnaisseurs tue
/// les gestes). Il route chaque geste vers une action unique. Logique pure (deltas en `Double`,
/// aucun framework UI) → testable. Voir `docs/PORT-SPEC.md §7.3`.
struct PlayerGestureArbiter {

    enum Side: Equatable { case left, right }

    /// Geste brut reçu de la couche UI (SwiftUI en M5).
    enum Gesture: Equatable {
        case tap
        /// Glissement vertical d'un côté de l'écran ; `delta` normalisé (−1…1, haut = +).
        case verticalDrag(side: Side, delta: Double)
        /// Glissement horizontal ; `delta` normalisé (−1…1, droite = +).
        case horizontalDrag(delta: Double)
    }

    /// Action résolue, à appliquer par le lecteur.
    enum Action: Equatable {
        case toggleControls
        case adjustVolume(Double)       // delta appliqué au volume (−1…1)
        case adjustBrightness(Double)   // delta appliqué à la luminosité (−1…1)
        case changeChannel(Int)         // ±1 (Direct uniquement)
        case none
    }

    let isLive: Bool
    /// Amplitude minimale d'un glissement horizontal pour valider un changement de chaîne.
    var channelSwipeThreshold: Double = 0.3

    func resolve(_ gesture: Gesture) -> Action {
        switch gesture {
        case .tap:
            return .toggleControls

        case let .verticalDrag(side, delta):
            // Droite = volume, gauche = luminosité. Actif que les contrôles soient visibles ou non.
            switch side {
            case .right: return .adjustVolume(delta)
            case .left:  return .adjustBrightness(delta)
            }

        case let .horizontalDrag(delta):
            // Changement de chaîne : **Direct uniquement**, au-delà du seuil.
            guard isLive, abs(delta) >= channelSwipeThreshold else { return .none }
            return .changeChannel(delta > 0 ? 1 : -1)
        }
    }
}
