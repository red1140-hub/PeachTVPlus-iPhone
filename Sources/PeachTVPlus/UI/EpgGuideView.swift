import SwiftUI

/// Guide horaire d'**une** chaîne (EPG du jour via `get_simple_data_table`, chargé **à la
/// demande** — jamais en masse). L'émission en cours est mise en évidence ; sur une chaîne à
/// archive, les émissions **terminées** offrent le **rattrapage** (timeshift). Lien de recherche
/// IMDb par titre (l'EPG Xtream n'a pas la distribution).
struct EpgGuideView: View {
    let channel: LiveChannel
    let container: AppContainer
    /// Appelé quand l'utilisateur lance un rattrapage ; le parent présente alors le lecteur.
    var onPlayCatchup: (PlaybackRequest) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var programmes: [EpgProgramme] = []
    @State private var isLoading = true

    private static let hm: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Chargement du guide…")
                } else if programmes.isEmpty {
                    ContentUnavailableView("Guide indisponible",
                                           systemImage: "calendar",
                                           description: Text("Aucune donnée horaire pour cette chaîne."))
                } else {
                    list
                }
            }
            .navigationTitle(channel.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
            }
            .task { await load() }
        }
    }

    private var list: some View {
        List(programmes) { prog in
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(timeRange(prog))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if isNow(prog) {
                        Text("EN COURS")
                            .font(.caption2.bold())
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.liveNow, in: Capsule())
                    }
                    Spacer()
                }
                Text(prog.title.isEmpty ? "(Sans titre)" : prog.title)
                    .font(.subheadline).lineLimit(2)
                if !prog.description.isEmpty {
                    Text(prog.description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack(spacing: 12) {
                    if canCatchup(prog) {
                        Button {
                            if let r = catchupRequest(prog) { onPlayCatchup(r) }
                        } label: {
                            Label("Rattrapage", systemImage: "clock.arrow.circlepath")
                        }
                        .tint(Theme.accent)
                    }
                    if !prog.title.isEmpty {
                        Button {
                            if let url = imdbURL(prog.title) { openURL(url) }
                        } label: {
                            Label("IMDb", systemImage: "magnifyingglass")
                        }
                    }
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.top, 2)
            }
            .padding(.vertical, 2)
        }
        .listStyle(.plain)
    }

    private func load() async {
        isLoading = true
        let p = await container.repository.fullEpg(streamId: channel.id)
        programmes = p.sorted { ($0.start ?? .distantPast) < ($1.start ?? .distantPast) }
        isLoading = false
    }

    private func isNow(_ p: EpgProgramme) -> Bool {
        guard let s = p.start, let e = p.end else { return false }
        let now = Date()
        return s <= now && now < e
    }

    /// Rattrapage possible : chaîne à archive + émission **terminée** avec bornes connues.
    private func canCatchup(_ p: EpgProgramme) -> Bool {
        guard channel.hasArchive, p.start != nil, let e = p.end else { return false }
        return e <= Date()
    }

    private func catchupRequest(_ p: EpgProgramme) -> PlaybackRequest? {
        guard let s = p.start, let e = p.end, let factory = container.activeFactory else { return nil }
        let minutes = max(1, Int(e.timeIntervalSince(s) / 60))
        let url = factory.timeshiftURL(streamId: channel.id, durationMinutes: minutes, start: s)
        return PlaybackRequest(url: url, title: channel.name, isLive: false, subtitle: p.title)
    }

    private func timeRange(_ p: EpgProgramme) -> String {
        let s = p.start.map { Self.hm.string(from: $0) } ?? "--:--"
        let e = p.end.map { Self.hm.string(from: $0) } ?? "--:--"
        return "\(s) – \(e)"
    }

    private func imdbURL(_ title: String) -> URL? {
        var comps = URLComponents(string: "https://www.imdb.com/find/")
        comps?.queryItems = [URLQueryItem(name: "q", value: title)]
        return comps?.url
    }
}
