import SwiftUI

/// Routage racine (M5) : connecté → shell à onglets ; sinon → écran de connexion.
/// La `SessionViewModel` (créée à partir du conteneur) porte l'état `isLoggedIn`.
struct RootView: View {
    let container: AppContainer
    @StateObject private var session: SessionViewModel
    @State private var showSplash = true

    init(container: AppContainer) {
        self.container = container
        _session = StateObject(wrappedValue: SessionViewModel(container: container))
    }

    var body: some View {
        ZStack {
            Group {
                if session.isLoggedIn {
                    MainShell(container: container, session: session)
                } else {
                    LoginView(session: session)
                }
            }
            if showSplash {
                SplashView().transition(.opacity)
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: 1_200_000_000) // ~1,2 s
            withAnimation(.easeOut(duration: 0.35)) { showSplash = false }
        }
    }
}

/// Écran de démarrage : logo PeachTV+ centré sur fond noir OLED, estompé après ~1,2 s.
/// (L'écran de lancement **système** est un simple fond noir — voir `UILaunchScreen` ; ce
/// splash SwiftUI ajoute le logo de marque, faute de splash vidéo pour l'instant.)
struct SplashView: View {
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 180, height: 180)
                .accessibilityLabel("PeachTV+")
        }
    }
}
