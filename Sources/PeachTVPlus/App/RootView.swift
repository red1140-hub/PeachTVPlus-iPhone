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
                SplashVideoView(onFinish: finishSplash).transition(.opacity)
            }
        }
    }

    private func finishSplash() {
        guard showSplash else { return }
        withAnimation(.easeOut(duration: 0.35)) { showSplash = false }
    }
}
