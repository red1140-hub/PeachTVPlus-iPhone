import SwiftUI

/// Vue racine — placeholder M0.
/// Remplacée au fil des jalons par le routage login → shell (Accueil/Recherche/
/// Favoris/Téléchargements/Réglages). Voir docs/PORT-SPEC.md §8.
struct RootView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "play.tv.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.orange)
                Text("PeachTV+")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                Text("Scaffold M0 — portage iOS en cours")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    RootView()
}
