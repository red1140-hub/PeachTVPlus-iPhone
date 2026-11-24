import SwiftUI

/// Calculs de stockage, **hors main actor** (fonctions `async` non isolées : parcours de fichiers).
enum StorageUsage {
    /// Somme des tailles réelles des fichiers locaux (défensif : fichier absent = 0).
    static func usedBytes(paths: [String]) async -> Int64 {
        var total: Int64 = 0
        for path in paths {
            if Task.isCancelled { break }
            let attrs = try? FileManager.default.attributesOfItem(atPath: path)
            if let size = (attrs?[.size] as? NSNumber)?.int64Value, size > 0 {
                total += size
            }
        }
        return total
    }

    /// Espace libre du volume (capacité disponible « usage important »), nil si indisponible.
    static func freeBytes() -> Int64? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

@MainActor
final class StorageViewModel: ObservableObject {
    @Published private(set) var usedBytes: Int64 = 0
    @Published private(set) var freeBytes: Int64?
    @Published private(set) var loaded = false

    private let container: AppContainer
    init(container: AppContainer) { self.container = container }

    func refresh() async {
        let paths = ((try? container.downloadStore.all()) ?? [])
            .filter { $0.downloadStatus == .completed }
            .compactMap { $0.localPath }
        let used = await StorageUsage.usedBytes(paths: paths)
        usedBytes = used
        freeBytes = StorageUsage.freeBytes()
        loaded = true
    }

    /// Part « utilisée par les téléchargements » dans (utilisé + libre), 0…1.
    var usedFraction: Double {
        guard let free = freeBytes, free >= 0 else { return 0 }
        let total = usedBytes + free
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(usedBytes) / Double(total)))
    }
}

/// Section Réglages « Stockage » : barre utilisé (accent néon) / libre (gris foncé).
struct StorageSection: View {
    @StateObject private var vm: StorageViewModel

    init(container: AppContainer) {
        _vm = StateObject(wrappedValue: StorageViewModel(container: container))
    }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(white: 0.2))
                        Capsule()
                            .fill(Theme.accent)
                            .frame(width: max(vm.usedFraction > 0 ? 6 : 0,
                                              geo.size.width * vm.usedFraction))
                    }
                }
                .frame(height: 12)
                .accessibilityHidden(true)

                HStack {
                    Label {
                        Text("Téléchargements : \(StorageUsage.format(vm.usedBytes))")
                    } icon: {
                        Circle().fill(Theme.accent).frame(width: 10, height: 10)
                    }
                    Spacer()
                    Label {
                        Text("Libre : \(freeText)")
                    } icon: {
                        Circle().fill(Color(white: 0.2)).frame(width: 10, height: 10)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Stockage")
            .accessibilityValue("Téléchargements : \(StorageUsage.format(vm.usedBytes)). Libre : \(freeText).")
        } header: {
            Text("Stockage")
        }
        .task { await vm.refresh() }
    }

    private var freeText: String {
        vm.freeBytes.map { StorageUsage.format($0) } ?? "—"
    }
}
