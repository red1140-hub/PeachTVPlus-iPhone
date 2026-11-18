import SwiftUI
import UIKit
import AVFoundation

/// Écran de démarrage **vidéo** : joue l'animation d'ouverture (`ouverture_peachtv.mp4`) en
/// accéléré **×1.5** (comme l'Android), puis appelle `onFinish`. Replis : si la vidéo manque ou
/// échoue → logo fixe + fin immédiate ; filet de sécurité 10 s pour ne jamais rester bloqué.
struct SplashVideoView: View {
    var onFinish: () -> Void

    @State private var player: AVPlayer?
    @State private var finished = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if let player {
                PlayerLayerView(player: player).ignoresSafeArea()
            } else {
                Image("Logo").resizable().scaledToFit().frame(width: 180, height: 180)
            }
        }
        .onAppear(perform: start)
    }

    private func start() {
        guard let url = Bundle.main.url(forResource: "ouverture_peachtv", withExtension: "mp4") else {
            finish(); return   // pas de vidéo → repli logo géré par l'absence de player, on termine
        }
        // Son autorisé pendant le splash (catégorie lecture), best-effort.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)

        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        player = p

        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { _ in finish() }

        p.play()
        p.rate = 1.5   // ×1.5 (après play, sinon la lecture repart à 1.0)

        // Filet de sécurité : on ne reste jamais coincé sur le splash.
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { finish() }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        onFinish()
    }
}

/// Couche vidéo nue (sans contrôles système), contrairement à `VideoPlayer` d'AVKit.
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerUIView {
        let view = PlayerLayerUIView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect   // ne pas rogner l'animation
        return view
    }

    func updateUIView(_ uiView: PlayerLayerUIView, context: Context) {}
}

final class PlayerLayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
