import Foundation
import Network

/// Orchestrateur du téléchargement hors-ligne ⭐ (port de Media3 `DownloadManager`).
///
/// `URLSession` **en arrière-plan** (poursuite app tuée, reprise `resumeData`), file d'attente
/// persistée (GRDB), plafond de parallélisme (`DownloadQueuePolicy`), **Wi-Fi uniquement**
/// (`NWPathMonitor` + `WiFiOnlyPolicy`), garde-fou d'espace disque, réinjection `__cred__` avec
/// **garde-fou d'hôte** (`XtreamURLFactory.reinjectCredentials`). Décisionnel testé dans les
/// politiques pures ; cette classe (intégration I/O) n'est pas couverte par la CI sans device.
/// Voir `docs/PORT-SPEC.md §6` et `docs/reliability-and-qa.md §3.5`.
final class DownloadManager: NSObject {

    static let backgroundIdentifier = "com.peachtvplus.app.downloads"

    private let store: DownloadStore
    private let credentialsProvider: (_ playlistId: String) -> XtreamCredentials?
    private var queuePolicy = DownloadQueuePolicy()
    private var wifiPolicy: WiFiOnlyPolicy

    private let workQueue: OperationQueue = {
        let q = OperationQueue(); q.maxConcurrentOperationCount = 1
        q.name = "com.peachtvplus.app.downloads.delegate"; return q
    }()
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Self.backgroundIdentifier)
        config.allowsCellularAccess = !wifiPolicy.wifiOnly
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        return URLSession(configuration: config, delegate: self, delegateQueue: workQueue)
    }()

    private let monitor = NWPathMonitor()
    private var currentPath: NetworkPathType = .wifi
    private var tasks: [String: URLSessionDownloadTask] = [:]   // contentKey → task

    /// Notifie l'UI (sur le thread principal) à chaque changement d'état agrégé.
    var onUpdate: (([String: DownloadUiState]) -> Void)?
    /// Posé par le `UIApplicationDelegate` (M5) pour `handleEventsForBackgroundURLSession`.
    var backgroundCompletionHandler: (() -> Void)?

    init(store: DownloadStore,
         wifiOnly: Bool = true,
         credentialsProvider: @escaping (_ playlistId: String) -> XtreamCredentials?) {
        self.store = store
        self.wifiPolicy = WiFiOnlyPolicy(wifiOnly: wifiOnly)
        self.credentialsProvider = credentialsProvider
        super.init()
        startMonitoring()
    }

    // MARK: - API publique

    func enqueue(contentKey: String, contentType: ContentType, playlistId: String,
                 title: String, maskedURL: String, ext: String, estimatedBytes: Int64 = 0) {
        workQueue.addOperation { [weak self] in
            guard let self else { return }
            if estimatedBytes > 0, let free = DiskSpaceGuard.systemFreeBytes(),
               !DiskSpaceGuard.canStart(estimatedBytes: estimatedBytes, freeBytes: free) {
                let err = DownloadError.classify(isDiskFull: true)
                self.saveFailed(contentKey: contentKey, contentType: contentType, playlistId: playlistId,
                                title: title, maskedURL: maskedURL, ext: ext, message: err.message)
                self.publish(); return
            }
            let record = DownloadRecord(
                contentKey: contentKey, contentType: contentType.rawValue, playlistId: playlistId,
                title: title, maskedURL: maskedURL, ext: DownloadPaths.sanitizedExtension(ext),
                localPath: nil, status: DownloadStatus.queued.rawValue, percent: 0,
                bytesDownloaded: 0, totalBytes: estimatedBytes > 0 ? Int(estimatedBytes) : nil,
                resumeData: nil, errorMessage: nil, updatedAt: Date().timeIntervalSince1970)
            try? self.store.upsert(record)
            self.scheduleNext()
            self.publish()
        }
    }

    func pause(_ contentKey: String) {
        workQueue.addOperation { [weak self] in
            guard let self else { return }
            guard let task = self.tasks[contentKey] else {
                try? self.store.setStatus(contentKey: contentKey, .paused); self.publish(); return
            }
            task.cancel(byProducingResumeData: { [weak self] data in
                self?.workQueue.addOperation {
                    guard let self else { return }
                    try? self.store.setResumeData(contentKey: contentKey, data)
                    try? self.store.setStatus(contentKey: contentKey, .paused)
                    self.tasks[contentKey] = nil
                    self.publish()
                }
            })
        }
    }

    func resume(_ contentKey: String) {
        workQueue.addOperation { [weak self] in
            guard let self else { return }
            try? self.store.setStatus(contentKey: contentKey, .queued)
            self.scheduleNext()
            self.publish()
        }
    }

    func remove(_ contentKey: String) {
        workQueue.addOperation { [weak self] in
            guard let self else { return }
            try? self.store.setStatus(contentKey: contentKey, .removing)
            self.tasks[contentKey]?.cancel()
            self.tasks[contentKey] = nil
            if let rec = try? self.store.record(contentKey: contentKey), let path = rec.localPath {
                try? FileManager.default.removeItem(atPath: path)
            }
            try? self.store.delete(contentKey: contentKey)
            self.scheduleNext()
            self.publish()
        }
    }

    /// Au démarrage : se rattacher aux tâches background survivantes, nettoyer les orphelins,
    /// relancer la file.
    func restore() {
        session.getAllTasks { [weak self] running in
            self?.workQueue.addOperation {
                guard let self else { return }
                for task in running.compactMap({ $0 as? URLSessionDownloadTask }) {
                    if let key = task.taskDescription { self.tasks[key] = task }
                }
                self.cleanOrphans()
                self.scheduleNext()
                self.publish()
            }
        }
    }

    // MARK: - Interne

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.workQueue.addOperation {
                guard let self else { return }
                self.currentPath = Self.classify(path)
                // Perte du lien autorisé → pauser les transferts en cours ; retour → relancer.
                if self.wifiPolicy.allows(self.currentPath) {
                    self.scheduleNext()
                } else {
                    self.pauseAllActiveForNetwork()
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.peachtvplus.app.downloads.nwpath"))
    }

    private static func classify(_ path: NWPath) -> NetworkPathType {
        guard path.status == .satisfied else { return .none }
        return path.isExpensive ? .cellular : .wifi
    }

    private func pauseAllActiveForNetwork() {
        for (key, task) in tasks {
            task.cancel(byProducingResumeData: { [weak self] data in
                self?.workQueue.addOperation {
                    guard let self else { return }
                    try? self.store.setResumeData(contentKey: key, data)
                    try? self.store.setStatus(contentKey: key, .paused)
                    self.tasks[key] = nil
                    self.publish()
                }
            })
        }
    }

    private func scheduleNext() {
        guard wifiPolicy.allows(currentPath) else { return }
        let records = (try? store.all()) ?? []
        for key in queuePolicy.nextToStart(records: records) { start(key) }
    }

    private func start(_ contentKey: String) {
        guard tasks[contentKey] == nil, let rec = try? store.record(contentKey: contentKey) else { return }

        guard let creds = credentialsProvider(rec.playlistId),
              let realURL = XtreamURLFactory.reinjectCredentials(into: rec.maskedURL, credentials: creds),
              URLGuard.isPlayable(realURL) else {
            // Garde-fou d'hôte / schéma : ne rien exposer, bloquer proprement.
            try? store.setStatus(contentKey: contentKey, .failed,
                                 error: "Identifiants indisponibles pour ce serveur.")
            return
        }

        let task: URLSessionDownloadTask
        if let resume = rec.resumeData {
            task = session.downloadTask(withResumeData: resume)
        } else {
            task = session.downloadTask(with: realURL)
        }
        task.taskDescription = contentKey
        tasks[contentKey] = task
        try? store.setStatus(contentKey: contentKey, .downloading)
        task.resume()
    }

    private func saveFailed(contentKey: String, contentType: ContentType, playlistId: String,
                            title: String, maskedURL: String, ext: String, message: String) {
        let record = DownloadRecord(
            contentKey: contentKey, contentType: contentType.rawValue, playlistId: playlistId,
            title: title, maskedURL: maskedURL, ext: DownloadPaths.sanitizedExtension(ext),
            localPath: nil, status: DownloadStatus.failed.rawValue, percent: 0,
            bytesDownloaded: 0, totalBytes: nil, resumeData: nil, errorMessage: message,
            updatedAt: Date().timeIntervalSince1970)
        try? store.upsert(record)
    }

    /// Supprime les fichiers du dossier Downloads non référencés par un enregistrement.
    private func cleanOrphans() {
        guard let dir = try? DownloadPaths.downloadsDirectory() else { return }
        let referenced = Set(((try? store.all()) ?? []).compactMap { $0.localPath.map { URL(fileURLWithPath: $0).lastPathComponent } })
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        for name in files where !referenced.contains(name) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
    }

    private func publish() {
        let states = ((try? store.all()) ?? []).reduce(into: [String: DownloadUiState]()) {
            $0[$1.contentKey] = $1.uiState
        }
        DispatchQueue.main.async { [weak self] in self?.onUpdate?(states) }
    }
}

// MARK: - URLSessionDownloadDelegate

extension DownloadManager: URLSessionDownloadDelegate {

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard let key = downloadTask.taskDescription else { return }
        let percent = totalBytesExpectedToWrite > 0
            ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0
        let total = totalBytesExpectedToWrite > 0 ? Int(totalBytesExpectedToWrite) : nil
        try? store.setProgress(contentKey: key, percent: percent,
                               bytes: Int(totalBytesWritten), total: total)
        publish()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let key = downloadTask.taskDescription,
              let rec = try? store.record(contentKey: key) else { return }
        // Déplacement SYNCHRONE (le fichier temporaire n'est valide que pendant ce callback).
        do {
            let dest = try DownloadPaths.localURL(for: key, ext: rec.ext)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: location, to: dest)
            try? store.setLocalPath(contentKey: key, dest.path)
            try? store.setStatus(contentKey: key, .completed)
        } catch {
            try? store.setStatus(contentKey: key, .failed, error: "Impossible d'enregistrer le fichier.")
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let key = task.taskDescription else { return }
        tasks[key] = nil

        guard let error else {
            // Succès : déjà traité dans didFinishDownloadingTo.
            scheduleNext(); publish(); return
        }

        // Reprise possible ? (resumeData fourni par le système)
        let nsError = error as NSError
        if let resume = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
            try? store.setResumeData(contentKey: key, resume)
        }

        let statusCode = (task.response as? HTTPURLResponse)?.statusCode
        let urlCode = (error as? URLError)?.code
        let classified = DownloadError.classify(statusCode: statusCode, urlErrorCode: urlCode)

        if classified.allowsRetry {
            // Coupure réseau / serveur : on met en pause (repris au retour), pas d'échec franc.
            try? store.setStatus(contentKey: key, .paused, error: classified.message)
        } else {
            try? store.setStatus(contentKey: key, .failed, error: classified.message)
        }
        scheduleNext(); publish()
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async { [weak self] in
            self?.backgroundCompletionHandler?()
            self?.backgroundCompletionHandler = nil
        }
    }

    /// Anti-downgrade HTTPS→HTTP : refuser une redirection qui exposerait les identifiants du
    /// chemin en clair (port de `docs/security.md §4.3`).
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        let from = task.originalRequest?.url?.scheme?.lowercased()
        let to = request.url?.scheme?.lowercased()
        if from == "https", to == "http" {
            RedactingLogger.error("DL : redirection HTTPS→HTTP refusée")
            completionHandler(nil)
        } else {
            completionHandler(request)
        }
    }
}
