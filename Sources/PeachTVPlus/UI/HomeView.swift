import SwiftUI

/// **Accueil** : en-tête à sous-onglets **Direct / Films / Séries** (onglets maison, plus étroits
/// et plus hauts, glissé horizontal) avec le logo agrandi à droite. Chaque section conserve sa
/// propre pile de navigation et masque sa barre (le nom de section n'est plus répété sous l'en-tête).
struct HomeView: View {
    let container: AppContainer
    @State private var section = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                SectionTabs(selection: $section)
                    .frame(maxWidth: 330)        // 4 onglets : un peu plus large qu'avant
                Spacer(minLength: 4)
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 46)            // logo agrandi (~+50 %)
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
                LocalVideosView(container: container).tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
    }
}

/// Onglets Direct / Films / Séries maison : hauteur confortable, actif en accent néon.
private struct SectionTabs: View {
    @Binding var selection: Int
    private let items = ["Direct", "Films", "Séries", "Appareil"]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(items.indices, id: \.self) { i in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { selection = i }
                } label: {
                    Text(items[i])
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)    // « Appareil » tient même à l'étroit
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)      // hauteur accrue
                        .background(selection == i ? Theme.accent : Color(white: 0.15),
                                    in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(selection == i ? Color.black : Color.primary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
