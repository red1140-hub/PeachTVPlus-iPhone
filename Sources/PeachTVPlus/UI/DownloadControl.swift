import SwiftUI
import Combine

/// Bouton de téléchargement **6 états** (port de `DownloadButton` Android), posé sur les fiches
/// film/épisode. Lit l'état courant depuis `downloadStore` (rafraîchi à l'apparition et toutes les
/// secondes tant qu'un transfert est actif), déclenche la mise en file / pause / reprise.
/// La progression détaillée reste visible dans l'onglet Téléchargements.
struct DownloadControl: View {
    let container: AppContainer
    let contentKey: String
    /// Construit et met en file le téléchargement (URL masquée + identifiants réinjectés par le manager).
    let enqueue: () -> Void
    /// Compact = icône seule (lignes d'épisodes) ; sinon icône + texte (fiche film).
    var compact: Bool = false

    @State private var state: DownloadButtonState = .notDownloaded
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Button(action: tap) { label }
            .buttonStyle(.bordered)
            .tint(Theme.accent)
            .onAppear(perform: refresh)
            .onReceive(ticker) { _ in if isActive { refresh() } }
            .accessibilityLabel(state.accessibilityLabel)
    }

    private var isActive: Bool {
        switch state {
        case .inProgress, .queued, .paused: return true
        default: return false
        }
    }

    @ViewBuilder private var label: some View {
        if compact {
            Image(systemName: iconName)
        } else {
            Label(text, systemImage: iconName)
        }
    }

    private var iconName: String {
        switch state {
        case .notDownloaded: return "arrow.down.circle"
        case .queued:        return "clock"
        case .inProgress:    return "stop.circle"
        case .paused:        return "arrow.clockwise.circle"
        case .completed:     return "checkmark.circle.fill"
        case .failed:        return "exclamationmark.circle"
        }
    }

    private var text: String {
        switch state {
        case .notDownloaded:     return "Télécharger"
        case .queued:            return "En file…"
        case .inProgress(let p): return "\(pct(p)) %"
        case .paused(let p):     return "Reprendre \(pct(p)) %"
        case .completed:         return "Hors ligne"
        case .failed:            return "Réessayer"
        }
    }

    private func pct(_ p: Double) -> Int { Int((p * 100).rounded()) }

    private func tap() {
        switch state {
        case .notDownloaded:        enqueue()
        case .inProgress:           container.downloadManager.pause(contentKey)
        case .paused, .failed:      container.downloadManager.resume(contentKey)
        case .queued, .completed:   break
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { refresh() }
    }

    private func refresh() {
        let rec = try? container.downloadStore.record(contentKey: contentKey)
        state = DownloadButtonState.from(rec?.uiState)
    }
}
