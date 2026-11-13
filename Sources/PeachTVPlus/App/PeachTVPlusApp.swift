import SwiftUI

/// Point d'entrée de l'app PeachTV+ (iOS/iPadOS).
///
/// M5 — câblage runtime : `AppContainer` (DI, writer GRDB unique, gestionnaire de
/// téléchargements), `AppDelegate` pour le réveil background des téléchargements, et routage
/// login → shell. Voir `docs/PORT-SPEC.md §8`.
@main
struct PeachTVPlusApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var container = AppContainer.live()

    var body: some Scene {
        WindowGroup {
            RootView(container: container)
                .preferredColorScheme(.dark) // thème sombre OLED forcé (comme Android)
                .task { container.start() }  // rattachement aux téléchargements background
        }
    }
}
