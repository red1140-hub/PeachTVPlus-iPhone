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

/// Onglets Direct / Films / Séries / Appareil maison : **icône + libellé**, l'onglet actif prend
/// l'icône colorée (orange néon) et le libellé en accent, l'inactif l'icône grise (reprise de la
/// règle Android « icône active gris → orangé »). Assets : `icon_<base>_on` / `icon_<base>_off`.
private struct SectionTabs: View {
    @Binding var selection: Int
    private let tabs: [(label: String, asset: String)] = [
        ("Direct", "direct"), ("Films", "films"), ("Séries", "series"), ("Appareil", "appareil")
    ]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(tabs.indices, id: \.self) { i in
                let selected = selection == i
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { selection = i }
                } label: {
                    VStack(spacing: 3) {
                        Image("icon_\(tabs[i].asset)_\(selected ? "on" : "off")")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 26)
                            .accessibilityHidden(true)
                        Text(tabs[i].label)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)    // « Appareil » tient même à l'étroit
                            .foregroundStyle(selected ? Theme.accent : Color.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(selected ? Theme.accent.opacity(0.14) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 10))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
