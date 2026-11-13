import SwiftUI
import UIKit
import MediaPlayer
import AVFoundation

/// Contrôle du volume système via un `MPVolumeView` **masqué** — la seule voie publique pour
/// régler le volume par programme sur iOS (M3b avait reporté ce câblage). Le `MPVolumeView`
/// doit vivre dans la hiérarchie de vues pour que son `UISlider` interne existe : on le place
/// hors écran dans le lecteur via `SystemVolumeHost`.
final class SystemVolumeController: ObservableObject {
    let volumeView = MPVolumeView(frame: .zero)

    private var slider: UISlider? {
        volumeView.subviews.compactMap { $0 as? UISlider }.first
    }

    /// Volume courant (repli sur la session audio si le slider n'est pas encore prêt).
    var current: Float { slider?.value ?? AVAudioSession.sharedInstance().outputVolume }

    func set(_ value: Float) {
        let clamped = max(0, min(1, value))
        let slider = self.slider
        DispatchQueue.main.async { slider?.setValue(clamped, animated: false) }
    }
}

/// Hôte invisible du `MPVolumeView` (0 px, non interactif) à insérer dans le lecteur.
struct SystemVolumeHost: UIViewRepresentable {
    let controller: SystemVolumeController

    func makeUIView(context: Context) -> MPVolumeView {
        let view = controller.volumeView
        view.alpha = 0.001
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}
