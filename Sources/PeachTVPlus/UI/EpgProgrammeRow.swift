import SwiftUI

/// Helpers EPG **partagés** par le guide en feuille (`EpgGuideView`) et le panneau Direct
/// inline (`ChannelEpgPanel`). Un seul endroit pour le formatage horaire, la détection
/// « en cours » et la construction de la requête de rattrapage (timeshift).
enum EpgFormat {
    static let hm: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "HH:mm"
        return f
    }()

    static func timeRange(_ p: EpgProgramme) -> String {
        let s = p.start.map { hm.string(from: $0) } ?? "--:--"
        let e = p.end.map { hm.string(from: $0) } ?? "--:--"
        return "\(s) – \(e)"
    }

    static func isNow(_ p: EpgProgramme) -> Bool {
        guard let s = p.start, let e = p.end else { return false }
        let now = Date()
        return s <= now && now < e
    }

    /// Rattrapage possible : chaîne à archive + émission **terminée** avec bornes connues.
    static func canCatchup(_ p: EpgProgramme, channel: LiveChannel) -> Bool {
        guard channel.hasArchive, p.start != nil, let e = p.end else { return false }
        return e <= Date()
    }

    /// `@MainActor` : lit `container.activeFactory` (isolé au main actor). Appelée uniquement
    /// depuis une action de bouton SwiftUI, donc déjà sur le main.
    @MainActor
    static func catchupRequest(_ p: EpgProgramme, channel: LiveChannel,
                               container: AppContainer) -> PlaybackRequest? {
        guard let s = p.start, let e = p.end, let factory = container.activeFactory else { return nil }
        let minutes = max(1, Int(e.timeIntervalSince(s) / 60))
        let url = factory.timeshiftURL(streamId: channel.id, durationMinutes: minutes, start: s)
        return PlaybackRequest(url: url, title: channel.name, isLive: false, subtitle: p.title)
    }

    static func imdbURL(_ title: String) -> URL? {
        var comps = URLComponents(string: "https://www.imdb.com/find/")
        comps?.queryItems = [URLQueryItem(name: "q", value: title)]
        return comps?.url
    }
}

/// Ligne d'une émission dans un EPG : plage horaire, badge « EN COURS », titre + résumé,
/// et actions **Rattrapage** (si archive + émission passée) / **IMDb** (recherche par titre).
struct EpgProgrammeRow: View {
    let prog: EpgProgramme
    let channel: LiveChannel
    let container: AppContainer
    var onCatchup: (PlaybackRequest) -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(EpgFormat.timeRange(prog))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                if EpgFormat.isNow(prog) {
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
                if EpgFormat.canCatchup(prog, channel: channel) {
                    Button {
                        if let r = EpgFormat.catchupRequest(prog, channel: channel, container: container) {
                            onCatchup(r)
                        }
                    } label: {
                        Label("Rattrapage", systemImage: "clock.arrow.circlepath")
                    }
                    .tint(Theme.accent)
                }
                if !prog.title.isEmpty {
                    Button {
                        if let url = EpgFormat.imdbURL(prog.title) { openURL(url) }
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
}

/// Texte défilant (marquee) : si le nom dépasse la largeur disponible, il défile lentement
/// d'avant en arrière ; sinon il reste fixe, aligné à gauche. Utilisé pour les noms de
/// chaîne longs dans la colonne Direct (reprend le défilement du nom côté Android).
struct MarqueeText: View {
    let text: String
    var font: Font = .caption

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var animate = false

    private var overflow: CGFloat { max(0, textWidth - containerWidth) }

    var body: some View {
        GeometryReader { geo in
            Text(text)
                .font(font)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .background(
                    GeometryReader { t in
                        Color.clear
                            .onAppear { textWidth = t.size.width }
                            .onChange(of: t.size.width) { _, v in textWidth = v }
                    }
                )
                .offset(x: animate ? -overflow - 10 : 0)
                .frame(width: geo.size.width, alignment: .leading)
                .clipped()
                .onAppear { containerWidth = geo.size.width; restart() }
                .onChange(of: geo.size.width) { _, v in containerWidth = v; restart() }
                .onChange(of: textWidth) { _, _ in restart() }
                .onChange(of: text) { _, _ in restart() }
        }
        .frame(height: 16)
    }

    private func restart() {
        animate = false
        guard overflow > 1 else { return }
        withAnimation(.linear(duration: max(3, Double(overflow) / 25)).delay(1).repeatForever(autoreverses: true)) {
            animate = true
        }
    }
}
