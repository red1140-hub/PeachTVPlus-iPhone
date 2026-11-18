import SwiftUI

@MainActor
final class DownloadsViewModel: ObservableObject {
    @Published private(set) var records: [DownloadRecord] = []

    private let container: AppContainer
    init(container: AppContainer) { self.container = container }

    func bind() {
        reloadNow()
        container.downloadManager.onUpdate = { [weak self] _ in
            // `publish()` dispatche déjà sur le thread principal.
            MainActor.assumeIsolated { self?.reloadNow() }
        }
    }

    func unbind() { container.downloadManager.onUpdate = nil }

    func pause(_ key: String) { container.downloadManager.pause(key) }
    func resume(_ key: String) { container.downloadManager.resume(key) }
    func remove(_ key: String) { container.downloadManager.remove(key) }

    var movies: [DownloadRecord] { records.filter { $0.contentType == ContentType.vod.rawValue } }
    var series: [DownloadRecord] { records.filter { $0.contentType == ContentType.series.rawValue } }
    var isEmpty: Bool { records.isEmpty }

    /// Requête de lecture **hors-ligne** depuis le fichier local (téléchargement terminé).
    func offlineRequest(_ rec: DownloadRecord) -> PlaybackRequest? {
        guard rec.downloadStatus == .completed, let path = rec.localPath else { return nil }
        return PlaybackRequest(url: URL(fileURLWithPath: path), title: rec.title, isLive: false)
    }

    private func reloadNow() {
        records = ((try? container.downloadStore.all()) ?? [])
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
}

/// Écran **Téléchargements** : sections Films / Séries, état par élément (pause/reprise/échec),
/// et **lecture hors-ligne** du fichier local au tap sur un élément terminé.
struct DownloadsView: View {
    @StateObject private var vm: DownloadsViewModel
    @State private var presentation: PlayerPresentation?

    init(container: AppContainer) {
        _vm = StateObject(wrappedValue: DownloadsViewModel(container: container))
    }

    var body: some View {
        NavigationStack {
            Group {
                if vm.isEmpty {
                    ContentUnavailableView("Aucun téléchargement",
                                           systemImage: "arrow.down.circle",
                                           description: Text("Les films et épisodes téléchargés s'afficheront ici, lisibles hors ligne."))
                } else {
                    list
                }
            }
            .navigationTitle("Téléchargements")
            .onAppear { vm.bind() }
            .onDisappear { vm.unbind() }
            .fullScreenCover(item: $presentation) { p in
                PlayerView(request: p.request, onClose: { presentation = nil })
            }
        }
    }

    private var list: some View {
        List {
            if !vm.movies.isEmpty {
                Section("Films") { ForEach(vm.movies, id: \.contentKey) { row($0) } }
            }
            if !vm.series.isEmpty {
                Section("Séries") { ForEach(vm.series, id: \.contentKey) { row($0) } }
            }
        }
    }

    private func row(_ item: DownloadRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.title).lineLimit(1)
                Spacer()
                statusControl(item)
            }
            if item.downloadStatus == .downloading || item.downloadStatus == .paused {
                ProgressView(value: item.percent)
                    .tint(item.downloadStatus == .paused ? .secondary : Theme.accent)
            }
            Text(statusLabel(item)).font(.caption).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let r = vm.offlineRequest(item) { presentation = PlayerPresentation(request: r) }
        }
        .swipeActions {
            Button("Supprimer", role: .destructive) { vm.remove(item.contentKey) }
        }
    }

    @ViewBuilder
    private func statusControl(_ item: DownloadRecord) -> some View {
        switch item.downloadStatus {
        case .downloading:
            Button { vm.pause(item.contentKey) } label: { Image(systemName: "pause.circle") }
                .buttonStyle(.borderless).accessibilityLabel("Mettre en pause")
        case .paused, .failed:
            Button { vm.resume(item.contentKey) } label: { Image(systemName: "arrow.clockwise.circle") }
                .buttonStyle(.borderless).accessibilityLabel("Reprendre")
        case .completed:
            Image(systemName: "play.circle.fill").foregroundStyle(Theme.accent)
        case .queued, .removing:
            ProgressView()
        }
    }

    private func statusLabel(_ item: DownloadRecord) -> String {
        switch item.downloadStatus {
        case .queued:      return "En file d'attente"
        case .downloading: return "Téléchargement \(Int((item.percent * 100).rounded())) %"
        case .paused:      return "En pause \(Int((item.percent * 100).rounded())) %"
        case .completed:   return "Disponible hors ligne — appuyer pour lire"
        case .failed:      return "Échec — appuyer sur ↻ pour réessayer"
        case .removing:    return "Suppression…"
        }
    }
}
