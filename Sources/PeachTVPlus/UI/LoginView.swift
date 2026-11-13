import SwiftUI

/// Écran de connexion : saisie serveur / utilisateur / mot de passe, avec garde-fou HTTP
/// (demande de consentement si serveur non sécurisé). Utilisé au premier lancement et pour
/// ajouter une liste depuis les Réglages.
struct LoginView: View {

    @ObservedObject var session: SessionViewModel
    /// Rappel optionnel (fermeture quand présenté en feuille depuis les Réglages).
    var onDone: (() -> Void)? = nil

    @State private var server = ""
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Adresse du serveur", text: $server)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Nom d'utilisateur", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Mot de passe", text: $password)
                        .textContentType(.password)
                } header: {
                    Text("Abonnement Xtream Codes")
                } footer: {
                    Text("L'adresse peut être saisie comme « serveur.com:8080 ». HTTPS recommandé.")
                }

                if let error = session.errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            Spacer()
                            if session.isWorking { ProgressView() } else { Text("Se connecter").bold() }
                            Spacer()
                        }
                    }
                    .disabled(session.isWorking || server.isEmpty || username.isEmpty)
                }
            }
            .navigationTitle("PeachTV+")
            .toolbar {
                if onDone != nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Fermer") { onDone?() }
                    }
                }
            }
            .alert("Serveur non sécurisé",
                   isPresented: Binding(get: { session.pendingCleartextHost != nil },
                                        set: { if !$0 { session.pendingCleartextHost = nil } })) {
                Button("Annuler", role: .cancel) { session.pendingCleartextHost = nil }
                Button("Autoriser le HTTP") {
                    session.pendingCleartextHost = nil
                    Task { await submit(allowCleartext: true) }
                }
            } message: {
                Text("Ce serveur utilise une connexion HTTP non chiffrée. Vos identifiants seront envoyés en clair. Continuer ?")
            }
        }
    }

    private func submit(allowCleartext: Bool = false) async {
        let ok = await session.login(server: server, username: username,
                                     password: password, allowCleartext: allowCleartext)
        if ok { onDone?() }
    }
}
