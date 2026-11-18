import SwiftUI

/// **Accueil** : en-tête à sous-onglets **Direct / Films / Séries** (segmenté + glissé horizontal)
/// avec le logo à droite, reproduisant l'en-tête de l'app Android. Chaque section conserve sa
/// propre pile de navigation (`NavigationStack`) et sa barre d'outils (catégories).
struct HomeView: View {
    let container: AppContainer
    @State private var section = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("Section", selection: $section) {
                    Text("Direct").tag(0)
                    Text("Films").tag(1)
                    Text("Séries").tag(2)
                }
                .pickerStyle(.segmented)

                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 30)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 6)

            // Sous-onglets glissables ; chaque page garde sa propre navigation.
            TabView(selection: $section) {
                LiveView(container: container).tag(0)
                MoviesView(container: container).tag(1)
                SeriesListView(container: container).tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
    }
}
