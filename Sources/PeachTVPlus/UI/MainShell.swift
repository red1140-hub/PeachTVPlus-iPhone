import SwiftUI

/// Shell principal à onglets (une fois connecté) : Direct / Recherche / Favoris /
/// Téléchargements / Réglages. Chaque onglet construit son propre ViewModel à partir du
/// conteneur. Voir `docs/PORT-SPEC.md §8`.
struct MainShell: View {
    let container: AppContainer
    @ObservedObject var session: SessionViewModel

    var body: some View {
        TabView {
            LiveView(container: container)
                .tabItem { Label("Direct", systemImage: "play.tv") }

            SearchView(container: container)
                .tabItem { Label("Recherche", systemImage: "magnifyingglass") }

            FavoritesView(container: container)
                .tabItem { Label("Favoris", systemImage: "star") }

            DownloadsView(container: container)
                .tabItem { Label("Téléchargements", systemImage: "arrow.down.circle") }

            SettingsView(session: session)
                .tabItem { Label("Réglages", systemImage: "gearshape") }
        }
        .tint(.orange)
    }
}
