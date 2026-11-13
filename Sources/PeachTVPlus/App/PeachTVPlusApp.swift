import SwiftUI

/// Point d'entrée de l'app PeachTV+ (iOS/iPadOS).
///
/// M0 — scaffold minimal, sans dépendance externe, pour un premier CI vert.
/// L'injection de dépendances (AppContainer) et le routage réel (login → shell)
/// arrivent avec les jalons M1+ (voir docs/PORT-SPEC.md).
@main
struct PeachTVPlusApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark) // thème sombre OLED forcé (comme Android)
        }
    }
}
