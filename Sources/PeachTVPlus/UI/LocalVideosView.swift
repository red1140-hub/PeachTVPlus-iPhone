import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
final class LocalVideosViewModel: ObservableObject {
    @Published var items: [MediaItem] = []
    @Published var isLoading = false

    let provider: LocalMediaProvider
    private let store: LocalMediaStore

    init(container: AppContainer) {
        self.store = container.localMediaStore
        self.provider = LocalMediaProvider(store: store)
    }

    func reload() async {
        isLoading = true
        items = await provider.listItems()
        isLoading = false
    }

    /// Importe des fichiers choisis : on crée un **signet** pendant l'accès sécurisé accordé
    /// par le picker (il survivra aux relances de l'app).
    func importFiles(_ urls: [URL]) {
        for url in urls {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            if let bm = try? url.bookmarkData() { store.addFileBookmark(bm) }
        }
        Task { await reload() }
    }

    func importFolder(_ url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        if let bm = try? url.bookmarkData() { store.addFolderBookmark(bm) }
        Task { await reload() }
    }

    func remove(_ item: MediaItem) {
        provider.remove(item)
        Task { await reload() }
    }
}

/// Onglet **Appareil** (après « Séries ») : vidéos stockées localement, choisies par
/// l'utilisateur via le picker système (aucune permission de stockage large). Tap → lecteur
/// **existant** avec l'URL locale. Lecture 100 % locale, aucun réseau. Sous-onglet de l'Accueil.
struct LocalVideosView: View {
    @StateObject private var vm: LocalVideosViewModel
    @State private var presentation: PlayerPresentation?
    @State private var playingItem: MediaItem?
    @State private var activePicker: PickerKind?

    private let container: AppContainer

    init(container: AppContainer) {
        self.container = container
        _vm = StateObject(wrappedValue: LocalVideosViewModel(container: container))
    }

    enum PickerKind: Identifiable {
        case files, folder
        var id: Int { hashValue }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                topBar
                Divider()
                content
            }
            .toolbar(.hidden, for: .navigationBar)
            .task { await vm.reload() }
            .sheet(item: $activePicker) { kind in
                switch kind {
                case .files:
                    DocumentPicker(contentTypes: [.movie, .video, .audiovisualContent],
                                   allowsMultiple: true) { vm.importFiles($0) }
                        .ignoresSafeArea()
                case .folder:
                    DocumentPicker(contentTypes: [.folder],
                                   allowsMultiple: false) { urls in
                        if let u = urls.first { vm.importFolder(u) }
                    }
                    .ignoresSafeArea()
                }
            }
            .fullScreenCover(item: $presentation, onDismiss: {
                if let it = playingItem { vm.provider.endAccess(it); playingItem = nil }
            }) { p in
                PlayerView(request: p.request, onClose: { presentation = nil })
            }
        }
    }

    private var topBar: some View {
        HStack {
            Text("Appareil").font(.headline)
            Spacer()
            Menu {
                Button { activePicker = .files } label: { Label("Fichiers", systemImage: "doc.badge.plus") }
                Button { activePicker = .folder } label: { Label("Dossier", systemImage: "folder.badge.plus") }
            } label: {
                Label("Ajouter", systemImage: "plus.circle.fill")
            }
            .tint(Theme.accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder private var content: some View {
        if vm.isLoading && vm.items.isEmpty {
            ProgressView("Lecture de la médiathèque…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.items.isEmpty {
            ContentUnavailableView {
                Label("Aucune vidéo locale", systemImage: "externaldrive.badge.plus")
            } description: {
                Text("Ajoutez des fichiers ou un dossier depuis l'appareil. Rien n'est envoyé sur le réseau.")
            } actions: {
                Button("Ajouter des fichiers") { activePicker = .files }
                    .buttonStyle(.borderedProminent).tint(Theme.accent)
            }
        } else {
            List {
                ForEach(vm.items) { item in
                    Button { play(item) } label: {
                        LocalVideoRow(item: item, provider: vm.provider)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) { vm.remove(item) } label: {
                            Label(vm.provider.isFolderChild(item) ? "Retirer le dossier" : "Retirer",
                                  systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .refreshable { await vm.reload() }
        }
    }

    private func play(_ item: MediaItem) {
        guard let url = vm.provider.beginAccess(item) else { return }
        playingItem = item
        presentation = PlayerPresentation(
            request: PlaybackRequest(url: url, title: item.title, isLive: false))
    }
}

/// Ligne d'une vidéo locale : vignette 16:9 + titre + durée. Vignette et durée générées
/// **paresseusement** à l'affichage (fluide sur une grosse médiathèque) puis mémorisées.
private struct LocalVideoRow: View {
    let item: MediaItem
    let provider: LocalMediaProvider

    @State private var thumb: UIImage?
    @State private var duration: TimeInterval?
    @State private var loaded = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.12))
                if let thumb {
                    Image(uiImage: thumb).resizable().scaledToFill()
                } else {
                    Image(systemName: "film").foregroundStyle(.secondary)
                }
            }
            .frame(width: 96, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.subheadline).lineLimit(2)
                if let duration {
                    Text(Self.hms(duration)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "play.circle").foregroundStyle(Theme.accent)
        }
        .padding(.vertical, 4)
        .task {
            guard !loaded else { return }
            loaded = true
            let m = await provider.metadata(for: item)
            duration = m.duration
            thumb = m.thumbnail
        }
    }

    private static func hms(_ s: TimeInterval) -> String {
        let t = Int(s.rounded())
        let h = t / 3600, m = (t % 3600) / 60, sec = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec)
                     : String(format: "%d:%02d", m, sec)
    }
}

/// Pont vers `UIDocumentPickerViewController` en mode **ouverture** (`asCopy: false`) : renvoie
/// des URLs **security-scoped** (équivalent `ACTION_OPEN_DOCUMENT`/`OPEN_DOCUMENT_TREE`), sans
/// copie ni permission de stockage large. L'utilisateur choisit lui-même fichiers ou dossier.
struct DocumentPicker: UIViewControllerRepresentable {
    let contentTypes: [UTType]
    let allowsMultiple: Bool
    let onPick: ([URL]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: false)
        picker.allowsMultipleSelection = allowsMultiple
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        init(onPick: @escaping ([URL]) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }
    }
}
