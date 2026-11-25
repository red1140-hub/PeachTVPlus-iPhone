import SwiftUI

// MARK: - Mesure (hors main actor)

/// Erreurs de mesure. Messages FR, jamais d'URL.
enum SpeedTestError: Error {
    case noPlaylist
    case badResponse
    case noData
}

/// Mesure du débit descendant. `nonisolated` + `async` : la boucle octet par octet tourne
/// hors du main actor. N'accepte et ne renvoie que des types `Sendable`. Ne logge rien.
enum SpeedTestMeter {
    /// Caps : 4 s ou 8 Mo (le premier atteint).
    static let maxSeconds: Double = 4
    static let maxBytes: Int = 8_000_000

    /// Retourne le débit en Mbps.
    nonisolated static func measure(url: URL) async throws -> Double {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10                 // inactivité réseau
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SpeedTestError.badResponse
        }

        let clock = ContinuousClock()
        let start = clock.now
        var received = 0
        var elapsed: Double = 0

        for try await _ in asyncBytes {
            received += 1
            // On ne lit l'horloge que tous les 32 Ko (coût négligeable).
            if received % 32_768 == 0 {
                elapsed = seconds(from: start, to: clock.now)
                if elapsed >= maxSeconds || received >= maxBytes { break }
            }
        }
        // Fin de séquence ou sortie au cap : durée finale.
        elapsed = seconds(from: start, to: clock.now)

        guard received > 0, elapsed > 0 else { throw SpeedTestError.noData }
        return Double(received) * 8 / elapsed / 1_000_000
    }

    nonisolated private static func seconds(from start: ContinuousClock.Instant,
                                            to end: ContinuousClock.Instant) -> Double {
        let d = start.duration(to: end)
        return Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
    }
}

// MARK: - ViewModel

@MainActor
final class SpeedTestViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case running
        case result(Double)
        case error(String)
    }

    @Published private(set) var state: State = .idle

    func run(container: AppContainer) async {
        guard state != .running else { return }
        state = .running

        guard let factory = container.activeFactory else {
            state = .error(String(localized: "Connecte une liste de lecture d'abord"))
            return
        }
        let channels = (try? container.catalogStore.liveChannels(categoryId: nil, limit: 3)) ?? []
        guard !channels.isEmpty else {
            state = .error(String(localized: "Connecte une liste de lecture d'abord"))
            return
        }

        // Une chaîne morte ne doit pas fausser le test : on essaie jusqu'à 3 chaînes.
        for channel in channels {
            let url = factory.liveStreamURL(id: channel.id)
            do {
                let mbps = try await SpeedTestMeter.measure(url: url)
                state = .result(mbps)
                return
            } catch {
                if Task.isCancelled { state = .idle; return }
                continue
            }
        }
        state = .error(String(localized: "Mesure impossible : le serveur n'a pas répondu. Réessaie dans un instant."))
    }

    static func verdict(for mbps: Double) -> String {
        switch mbps {
        case ..<3:  return String(localized: "Ça rame en titi 🐌")
        case ..<10: return String(localized: "Correct, sans plus")
        case ..<25: return String(localized: "Ça roule ben")
        case ..<60: return String(localized: "Vitesse de feu 🔥")
        default:    return String(localized: "Pas pire, ça déboule !")
        }
    }
}

// MARK: - Section Réglages

struct SpeedTestSection: View {
    let container: AppContainer
    @StateObject private var model = SpeedTestViewModel()

    var body: some View {
        Section {
            Button {
                Task { await model.run(container: container) }
            } label: {
                HStack {
                    Label("Lancer le test", systemImage: "speedometer")
                    Spacer()
                    if model.state == .running { ProgressView() }
                }
            }
            .disabled(model.state == .running)

            switch model.state {
            case .idle, .running:
                EmptyView()
            case .result(let mbps):
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(Self.format(mbps)) Mbps")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Theme.accent)
                    Text(SpeedTestViewModel.verdict(for: mbps))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            case .error(let message):
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Test de vitesse")
        } footer: {
            Text("Télécharge brièvement un flux de ton serveur (4 secondes ou 8 Mo au maximum) pour estimer ton débit.")
        }
    }

    private static func format(_ mbps: Double) -> String {
        mbps.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "fr_CA")))
    }
}
