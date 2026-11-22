import SwiftUI

struct SettingsView: View {
    @ObservedObject var session: SessionViewModel
    @State private var showAddList = false
    @State private var isSyncing = false
    @State private var editing: Playlist?

    private var container: AppContainer { session.container }

    var body: some View {
        NavigationStack {
            Form {
                playlistsSection
                securitySection
                catalogSection
                aboutSection
                accountSection
            }
            .navigationTitle("Réglages")
            .sheet(isPresented: $showAddList) {
                LoginView(session: session, onDone: { showAddList = false })
            }
            .sheet(item: $editing) { playlist in
                EditPlaylistView(session: session, playlist: playlist,
                                 onDone: { editing = nil })
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
                .swipeActions(edge: .trailing) {
                    Button("Retirer", role: .destructive) { session.remove(playlist.id) }
                }
                .swipeActions(edge: .leading) {
                    Button("Modifier") { editing = playlist }.tint(.blue)
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

    private var aboutSection: some View {
        Section("À propos") {
            NavigationLink {
                ChangelogView()
            } label: {
                Label("Nouveautés", systemImage: "sparkles")
            }
            HStack {
                Text("Version")
                Spacer()
                Text(Changelog.currentVersion).foregroundStyle(.secondary)
            }
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

// MARK: - Édition d'une liste de lecture (sans la recréer)

/// Modifie **adresse / utilisateur / mot de passe** d'une liste existante. Changer seulement le
/// mot de passe garde l'`id` dérivé → favoris et catalogue conservés ; changer serveur ou
/// utilisateur donne un nouvel `id` (données scopées à l'ancien purgées). Le mot de passe est
/// masqué par défaut, révélable à la demande (reprise de la posture Android).
struct EditPlaylistView: View {
    @ObservedObject var session: SessionViewModel
    let playlist: Playlist
    var onDone: () -> Void

    @State private var server: String
    @State private var username: String
    @State private var password: String
    @State private var revealPassword = false
    @State private var error: String?
    @State private var cleartextHost: String?

    init(session: SessionViewModel, playlist: Playlist, onDone: @escaping () -> Void) {
        self.session = session
        self.playlist = playlist
        self.onDone = onDone
        _server = State(initialValue: playlist.credentials.serverUrl)
        _username = State(initialValue: playlist.credentials.username)
        _password = State(initialValue: playlist.credentials.password)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Serveur") {
                    TextField("Adresse du serveur", text: $server)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
                Section("Identifiants") {
                    TextField("Nom d'utilisateur", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    HStack {
                        Group {
                            if revealPassword {
                                TextField("Mot de passe", text: $password)
                            } else {
                                SecureField("Mot de passe", text: $password)
                            }
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        Button {
                            revealPassword.toggle()
                        } label: {
                            Image(systemName: revealPassword ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(revealPassword ? "Masquer le mot de passe" : "Afficher le mot de passe")
                    }
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red).font(.callout) }
                }
            }
            .navigationTitle("Modifier la liste")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { onDone() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }
                        .disabled(server.trimmingCharacters(in: .whitespaces).isEmpty
                                  || username.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("Serveur non chiffré",
                   isPresented: Binding(get: { cleartextHost != nil },
                                        set: { if !$0 { cleartextHost = nil } })) {
                Button("Autoriser et enregistrer") { save(allowCleartext: true) }
                Button("Annuler", role: .cancel) { cleartextHost = nil }
            } message: {
                Text("\(cleartextHost ?? "Ce serveur") utilise HTTP : vos identifiants transiteraient en clair. À n'autoriser que pour un serveur de confiance.")
            }
        }
    }

    private func save(allowCleartext: Bool = false) {
        if session.updatePlaylist(oldId: playlist.id, server: server, username: username,
                                  password: password, allowCleartext: allowCleartext) {
            onDone()
        } else if let host = session.pendingCleartextHost {
            session.pendingCleartextHost = nil      // consommé → on demande confirmation
            cleartextHost = host
        } else {
            error = session.errorMessage ?? "Impossible d'enregistrer la liste."
        }
    }
}

// MARK: - Changelog (Nouveautés)

/// Historique des versions, affiché dans Réglages → Nouveautés.
enum Changelog {
    static let currentVersion = entries.first?.version ?? "—"

    struct Entry: Identifiable {
        var id: String { version }
        let version: String
        let date: String
        let lines: [String]
    }

    static let entries: [Entry] = [
        Entry(version: "1.13", date: "2026-11",
              lines: [
                "Nouvel onglet « Appareil » : lecture de vos fichiers vidéo locaux.",
                "Direct repensé en deux panneaux : chaînes à gauche, grille horaire à droite.",
                "Lecteur : choix de la piste audio et des sous-titres, aide des gestes.",
                "Réglages : modifier une liste (adresse / identifiants) sans la recréer.",
              ]),
        Entry(version: "1.12", date: "2026-11",
              lines: [
                "Séries : lecture enchaînée des épisodes (glisser, auto, retour fiche).",
                "Guide horaire (EPG) et rattrapage au lecteur Direct.",
                "Téléchargement hors-ligne câblé (fiches + lecture locale).",
              ]),
    ]
}

struct ChangelogView: View {
    var body: some View {
        List {
            ForEach(Changelog.entries) { entry in
                Section("Version \(entry.version) · \(entry.date)") {
                    ForEach(entry.lines, id: \.self) { line in
                        Label(line, systemImage: "checkmark.seal")
                            .labelStyle(.titleAndIcon)
                            .font(.callout)
                    }
                }
            }
        }
        .navigationTitle("Nouveautés")
        .navigationBarTitleDisplayMode(.inline)
    }
}
