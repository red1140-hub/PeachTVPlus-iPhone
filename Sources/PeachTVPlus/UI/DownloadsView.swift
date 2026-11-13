import SwiftUI

@MainActor
final class DownloadsViewModel: ObservableObject {
    @Published private(set) var items: [DownloadUiState] = []

    private let container: AppContainer
    init(container: AppContainer) { self.container = container }

    func bind() {
        reloadNow()
        container.downloadManager.onUpdate = { [weak self] states in
            // `publish()` dispatche déjà sur le thread principal.
            MainActor.assumeIsolated { self?.items = Self.sorted(states) }
        }
    }

    func unbind() { container.downloadManager.onUpdate = nil }

    func pause(_ key: String) { container.downloadManager.pause(key) }
    func resume(_ key: String) { container.downloadManager.resume(key) }
    func remove(_ key: String) { container.downloadManager.remove(key) }

    private func reloadNow() {
        let states = ((try? container.downloadStore.all()) ?? [])
            .reduce(into: [String: DownloadUiState]()) { $0[$1.contentKey] = $1.uiState }
        items = Self.sorted(states)
    }

    private static func sorted(_ states: [String: DownloadUiState]) -> [DownloadUiState] {
        states.values.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
}

struct DownloadsView: View {
    @StateObject private var vm: DownloadsViewModel

    init(container: AppContainer) {
        _vm = StateObject(wrappedValue: DownloadsViewModel(container: container))
    }

    var body: some View {
        NavigationStack {
            Group {
                if vm.items.isEmpty {
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
        }
    }

    private var list: some View {
        List(vm.items, id: \.contentKey) { item in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(item.title).lineLimit(1)
                    Spacer()
                    statusControl(for: item)
                }
                if item.status == .downloading || item.status == .paused {
                    ProgressView(value: item.percent)
                        .tint(item.status == .paused ? .secondary : .orange)
                }
                Text(statusLabel(item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .swipeActions {
                Button("Supprimer", role: .destructive) { vm.remove(item.contentKey) }
            }
        }
    }

    @ViewBuilder
    private func statusControl(for item: DownloadUiState) -> some View {
        switch item.status {
        case .downloading:
            Button { vm.pause(item.contentKey) } label: { Image(systemName: "pause.circle") }
                .accessibilityLabel("Mettre en pause")
        case .paused, .failed:
            Button { vm.resume(item.contentKey) } label: { Image(systemName: "arrow.clockwise.circle") }
                .accessibilityLabel("Reprendre")
        case .completed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .queued, .removing:
            ProgressView()
        }
    }

    private func statusLabel(_ item: DownloadUiState) -> String {
        switch item.status {
        case .queued:      return "En file d'attente"
        case .downloading: return "Téléchargement \(Int((item.percent * 100).rounded())) %"
        case .paused:      return "En pause \(Int((item.percent * 100).rounded())) %"
        case .completed:   return "Disponible hors ligne"
        case .failed:      return "Échec — appuyer pour réessayer"
        case .removing:    return "Suppression…"
        }
    }
}
