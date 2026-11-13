import Foundation

/// Emplacement et **noms de fichiers générés localement** (anti path-traversal) des médias
/// hors-ligne. On ne dérive **jamais** le nom d'un champ serveur (titre, nom renvoyé) : nom
/// 100% local (hash de `streamId` + UUID), extension dans une allowlist, titre « joli » gardé
/// en métadonnée GRDB. Dossier `Application Support/Downloads/`, **exclu du backup iCloud**.
/// Port de `docs/security.md §5.2–5.3`.
enum DownloadPaths {
    static let allowedExt: Set<String> = ["mp4", "mkv", "ts", "m4v", "mov"]
    static let folderName = "Downloads"

    /// Extension sûre : l'entrée si elle est dans l'allowlist, sinon repli `mp4`. Pure.
    static func sanitizedExtension(_ raw: String) -> String {
        let ext = raw.lowercased()
        return allowedExt.contains(ext) ? ext : "mp4"
    }

    /// Nom de fichier **sans aucune donnée serveur** : aucun séparateur de chemin possible. Pure.
    static func safeFileName(for streamId: String, ext raw: String) -> String {
        "\(abs(streamId.hashValue))-\(UUID().uuidString).\(sanitizedExtension(raw))"
    }

    /// Dossier des téléchargements (créé si besoin), exclu de la sauvegarde iCloud.
    static func downloadsDirectory() throws -> URL {
        var base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true).appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try? base.excludeFromBackup()
        return base
    }

    /// URL locale finale, **vérifiée sous le dossier cible** (défense en profondeur `canonicalPath`).
    static func localURL(for streamId: String, ext raw: String) throws -> URL {
        let base = try downloadsDirectory()
        let candidate = base.appendingPathComponent(safeFileName(for: streamId, ext: raw))

        let baseReal = base.standardizedFileURL.resolvingSymlinksInPath().path
        let candReal = candidate.standardizedFileURL.resolvingSymlinksInPath().path
        guard candReal.hasPrefix(baseReal + "/") else { throw URLError(.badURL) }
        return candidate
    }
}
