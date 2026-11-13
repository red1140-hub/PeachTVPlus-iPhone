import SwiftUI
import UIKit

/// Pont SwiftUI → UIKit : fournit au `PlaybackCoordinator` la vue noire où le moteur courant
/// (AVPlayerLayer ou drawable VLC) s'affiche. Le coordinateur se charge de (ré)attacher la
/// surface à chaque bascule de moteur ; cette vue ne connaît aucun moteur.
struct VideoSurfaceView: UIViewRepresentable {

    let coordinator: PlaybackCoordinator

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        view.isUserInteractionEnabled = false   // les gestes sont captés par l'overlay SwiftUI
        coordinator.attachRenderSurface(view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
