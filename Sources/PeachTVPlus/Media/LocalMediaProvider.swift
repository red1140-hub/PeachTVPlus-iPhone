import Foundation
import AVFoundation
import UIKit

/// Persiste les **signets sécurisés** (security-scoped bookmarks) des fichiers et dossiers que
/// l'utilisateur a choisis via le picker système. Ce ne sont PAS des identifiants : de simples
/// références d'accès à des fichiers **locaux**. Stockés en clair (`UserDefaults`) — aucune
/// donnée sensible, aucun réseau. (L'interdiction « pas d'identifiants en UserDefaults » du
/// projet vise les mots de passe Xtream, pas ces références de fichiers.)
final class LocalMediaStore {
    private let defaults: UserDefaults
    private let fileKey = "localMedia.fileBookmarks"
    private let folderKey = "localMedia.folderBookmarks"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func fileBookmarks() -> [Data] { (defaults.array(forKey: fileKey) as? [Data]) ?? [] }
    func folderBookmarks() -> [Data] { (defaults.array(forKey: folderKey) as? [Data]) ?? [] }

    func addFileBookmark(_ data: Data) {
        var all = fileBookmarks()
        guard !all.contains(data) else { return }
        all.append(data); defaults.set(all, forKey: fileKey)
    }
    func addFolderBookmark(_ data: Data) {
        var all = folderBookmarks()
        guard !all.contains(data) else { return }
        all.append(data); defaults.set(all, forKey: folderKey)
    }
    func removeFileBookmark(_ data: Data) {
        defaults.set(fileBookmarks().filter { $0 != data }, forKey: fileKey)
    }
    func removeFolderBookmark(_ data: Data) {
        defaults.set(folderBookmarks().filter { $0 != data }, forKey: folderKey)
    }
}

/// Source de contenu **100 % locale** (`file://`), première implémentation de `MediaProvider`.
/// Les fichiers/dossiers viennent du picker système (accès restreint, pas de permission large).
/// Aucun appel réseau. L'accès sécurisé (security scope) est ouvert au moment de la lecture et
/// refermé à la fermeture du lecteur (`beginAccess` / `endAccess`).
final class LocalMediaProvider: MediaProvider {

    private let store: LocalMediaStore
    private let videoExtensions: Set<String> = [
        "mp4", "m4v", "mov", "mkv", "avi", "ts", "m2ts", "mts",
        "webm", "flv", "wmv", "mpg", "mpeg", "3gp", "ogv"
    ]

    /// Résolution courante `item.id → source` (reconstituée à chaque `listItems`).
    private struct Resolved {
        let playURL: URL              // fichier à lire
        let scopeURL: URL             // URL dont il faut ouvrir le security scope pendant la lecture
        let fileBookmark: Data?       // signet du fichier (fichiers individuels)
        let folderBookmark: Data?     // signet du dossier parent (enfants de dossier)
    }
    private var resolved: [String: Resolved] = [:]
    /// `listItems` (async, hors main) écrit la table pendant que des lignes la lisent en
    /// parallèle → accès protégé par verrou.
    private let lock = NSLock()

    private func lookup(_ id: String) -> Resolved? {
        lock.lock(); defer { lock.unlock() }
        return resolved[id]
    }

    /// Écriture synchrone de la table résolue. **Synchrone exprès** : `NSLock.lock()` est
    /// interdit dans un contexte `async` (annoté `noasync`), donc on verrouille hors de
    /// `listItems()` (qui est `async`).
    private func commit(_ map: [String: Resolved]) {
        lock.lock(); resolved = map; lock.unlock()
    }

    init(store: LocalMediaStore) { self.store = store }

    // MARK: MediaProvider

    func listItems() async -> [MediaItem] {
        var items: [MediaItem] = []
        var map: [String: Resolved] = [:]

        // Fichiers choisis individuellement.
        for bm in store.fileBookmarks() {
            guard let url = resolveBookmark(bm) else { continue }
            let id = "file:" + url.absoluteString
            map[id] = Resolved(playURL: url, scopeURL: url, fileBookmark: bm, folderBookmark: nil)
            items.append(MediaItem(id: id, title: url.deletingPathExtension().lastPathComponent))
        }

        // Dossiers choisis → énumération des vidéos qu'ils contiennent.
        for fbm in store.folderBookmarks() {
            guard let folderURL = resolveBookmark(fbm) else { continue }
            let didAccess = folderURL.startAccessingSecurityScopedResource()
            defer { if didAccess { folderURL.stopAccessingSecurityScopedResource() } }
            for url in enumerateVideos(in: folderURL) {
                let id = "folder:" + url.absoluteString
                map[id] = Resolved(playURL: url, scopeURL: folderURL,
                                   fileBookmark: nil, folderBookmark: fbm)
                items.append(MediaItem(id: id, title: url.deletingPathExtension().lastPathComponent))
            }
        }

        commit(map)
        return items.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func resolveStreamURL(_ item: MediaItem) -> URL? { lookup(item.id)?.playURL }

    // MARK: Accès sécurisé (à encadrer autour de la lecture)

    /// Ouvre le security scope et renvoie l'URL lisible ; à appeler juste avant de présenter
    /// le lecteur. Renvoie `nil` si l'élément n'est plus résolu.
    func beginAccess(_ item: MediaItem) -> URL? {
        guard let r = lookup(item.id) else { return nil }
        _ = r.scopeURL.startAccessingSecurityScopedResource()
        return r.playURL
    }

    /// Referme le security scope ouvert par `beginAccess` ; à appeler à la fermeture du lecteur.
    func endAccess(_ item: MediaItem) {
        lookup(item.id)?.scopeURL.stopAccessingSecurityScopedResource()
    }

    /// Retire l'élément de la médiathèque : un fichier individuel, ou le **dossier parent**
    /// entier pour un enfant de dossier (on ne retire pas un seul fichier d'un dossier importé).
    /// `isFolderChild` indique au besoin quel libellé afficher.
    func isFolderChild(_ item: MediaItem) -> Bool { lookup(item.id)?.folderBookmark != nil }

    func remove(_ item: MediaItem) {
        guard let r = lookup(item.id) else { return }
        if let fb = r.folderBookmark { store.removeFolderBookmark(fb) }
        else if let b = r.fileBookmark { store.removeFileBookmark(b) }
    }

    // MARK: Métadonnées (durée + vignette), calculées paresseusement par ligne

    func metadata(for item: MediaItem) async -> (duration: TimeInterval?, thumbnail: UIImage?) {
        guard let r = lookup(item.id) else { return (nil, nil) }
        let didAccess = r.scopeURL.startAccessingSecurityScopedResource()
        defer { if didAccess { r.scopeURL.stopAccessingSecurityScopedResource() } }

        let asset = AVURLAsset(url: r.playURL)
        var duration: TimeInterval?
        if let d = try? await asset.load(.duration) {
            let s = CMTimeGetSeconds(d)
            if s.isFinite && s > 0 { duration = s }
        }

        var thumb: UIImage?
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 320, height: 180)
        let at = CMTime(seconds: min(duration ?? 1, 5), preferredTimescale: 600)
        if let (cg, _) = try? await generator.image(at: at) {
            thumb = UIImage(cgImage: cg)
        }
        return (duration, thumb)
    }

    // MARK: Privé

    private func resolveBookmark(_ data: Data) -> URL? {
        var stale = false
        // iOS : les signets du document picker sont automatiquement « security-scoped »
        // (pas d'option `.withSecurityScope`, qui est propre à macOS).
        return try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil,
                        bookmarkDataIsStale: &stale)
    }

    private func enumerateVideos(in folder: URL) -> [URL] {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: folder,
                                     includingPropertiesForKeys: [.isRegularFileKey],
                                     options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
            return []
        }
        var out: [URL] = []
        for case let url as URL in en where videoExtensions.contains(url.pathExtension.lowercased()) {
            out.append(url)
        }
        return out
    }
}
