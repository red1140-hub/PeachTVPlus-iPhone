import SwiftUI

struct SettingsView: View {
    @ObservedObject var session: SessionViewModel
    @State private var showAddList = false
    @State private var isSyncing = false

    private var container: AppContainer { session.container }

    var body: some View {
        NavigationStack {
            Form {
                playlistsSection
                securitySection
                catalogSection
                accountSection
            }
            .navigationTitle("Réglages")
            .sheet(isPresented: $showAddList) {
                LoginView(session: session, onDone: { showAddList = false })
            }
        }
    }

    private var playlistsSection: some View {
        Section("Listes de lecture") {
            ForEach(session.playlists) { playlist in
                Button {
                    session.switchTo(playlist.id)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(playlist.displayName).foregroundStyle(.primary)
                            Text(playlist.credentials.username)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if playlist.id == session.activeId {
                            Image(systemName: "checkmark").foregroundStyle(.orange)
                        }
                    }
                }
                .swipeActions {
                    Button("Retirer", role: .destructive) { session.remove(playlist.id) }
                }
            }
            Button {
                showAddList = true
            } label: {
                Label("Ajouter une liste", systemImage: "plus")
            }
        }
    }

    @ViewBuilder
    private var securitySection: some View {
        let insecure = session.playlists.filter { !$0.credentials.isSecure }
        if !insecure.isEmpty {
            Section {
                ForEach(insecure) { playlist in
                    if let host = playlist.credentials.host {
                        Toggle("Autoriser le HTTP pour \(host)", isOn: Binding(
                            get: { container.consent.hasConsented(host: host) },
                            set: { allow in
                                if allow { container.consent.grant(host: host) }
                                else { container.consent.revoke(host: host) }
                            }
                        ))
                    }
                }
            } header: {
                Text("Sécurité")
            } footer: {
                Text("HTTPS est recommandé. Le HTTP envoie vos identifiants en clair : à n'autoriser que pour un serveur de confiance.")
            }
        }
    }

    private var catalogSection: some View {
        Section("Catalogue") {
            Button {
                isSyncing = true
                Task {
                    await container.catalogSync.sync()
                    isSyncing = false
                }
            } label: {
                HStack {
                    Label("Resynchroniser le catalogue", systemImage: "arrow.triangle.2.circlepath")
                    Spacer()
                    if isSyncing { ProgressView() }
                }
            }
            .disabled(isSyncing)
        }
    }

    private var accountSection: some View {
        Section {
            Button("Se déconnecter", role: .destructive) { session.logout() }
        } footer: {
            Text("La déconnexion retire toutes les listes et efface le cache local (films, favoris, téléchargements).")
        }
    }
}
