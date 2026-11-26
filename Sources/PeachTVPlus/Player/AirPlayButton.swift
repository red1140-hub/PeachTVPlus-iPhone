import SwiftUI
import AVKit

/// Bouton **AirPlay** natif : enveloppe l'`AVRoutePickerView` d'AVKit, qui ouvre le sélecteur de
/// routes du système (AirPlay, haut-parleurs Bluetooth, Apple TV…) et reflète l'état de connexion.
/// C'est la voie « AirPlay d'abord » du portage (Google Cast viendra en post-v1). Le routage réel
/// est géré par le système dès que `AVPlayer.allowsExternalPlayback` est vrai (cf. `AVPlayerEngine`).
struct AirPlayButton: UIViewRepresentable {
    var tint: UIColor = .white

    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = tint                       // icône au repos
        picker.activeTintColor = UIColor(Theme.accent) // icône quand une route est active
        picker.prioritizesVideoDevices = true          // privilégie les appareils vidéo (Apple TV)
        picker.backgroundColor = .clear
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
