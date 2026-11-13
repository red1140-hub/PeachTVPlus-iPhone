import UIKit

/// Capte le réveil background de l'`URLSession` de téléchargement : iOS relance l'app (ou la
/// réveille) quand des transferts background finissent et fournit un `completionHandler` à
/// appeler une fois les événements traités (voir `DownloadManager.urlSessionDidFinishEvents`).
final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        guard identifier == DownloadManager.backgroundIdentifier else {
            completionHandler()
            return
        }
        Task { @MainActor in
            AppContainer.shared?.downloadManager.backgroundCompletionHandler = completionHandler
        }
    }
}
