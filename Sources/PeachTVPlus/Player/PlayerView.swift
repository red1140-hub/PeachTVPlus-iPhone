import SwiftUI
import UIKit
import Combine

/// Ce qu'on demande au lecteur d'ouvrir. Construit par l'appelant (chaîne Live, film, épisode,
/// rattrapage) à partir d'une URL déjà fabriquée par `XtreamURLFactory` (M1).
struct PlaybackRequest: Equatable {
    let url: URL
    let title: String
    let isLive: Bool
    var subtitle: String? = nil
    var profile: BufferProfile = .default
}

/// Programme EPG « maintenant / ensuite » à afficher en surimpression (optionnel).
struct NowNext: Equatable {
    let now: String
    let next: String?
}

/// Écran lecteur plein écran (M3b). Pilote un `PlaybackCoordinator` (bascule AVPlayer↔VLC +
/// retry), superpose les contrôles, et route **tous** les gestes via `PlayerGestureArbiter`
/// (un seul routeur, leçon Android). La grille EPG 12 h et l'intégration au shell relèvent de M5.
struct PlayerView: View {

    let request: PlaybackRequest
    var nowNext: NowNext? = nil
    var onClose: () -> Void = {}
    /// Direct uniquement : glissement horizontal → ±1 chaîne. L'appelant (M5) change la requête.
    var onChangeChannel: (Int) -> Void = { _ in }

    @StateObject private var coordinator = PlaybackCoordinator()
    @StateObject private var volume = SystemVolumeController()

    @State private var controlsVisible = true
    @State private var hideWorkItem: DispatchWorkItem?
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var isScrubbing = false

    // HUD volume/luminosité
    @State private var hud: HUD?
    @State private var dragSide: PlayerGestureArbiter.Side?
    @State private var baselineBrightness: Double = 0
    @State private var baselineVolumeHUD: Double = 0.5

    private enum HUD: Equatable { case volume(Double), brightness(Double) }

    private let ticker = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                VideoSurfaceView(coordinator: coordinator)
                    .ignoresSafeArea()

                // MPVolumeView masqué : permet de régler le volume système réel.
                SystemVolumeHost(controller: volume)
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)

                gestureLayer(size: geo.size)

                if controlsVisible {
                    controlsOverlay
                        .transition(.opacity)
                }

                if isBuffering {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(1.4)
                }

                if let hud {
                    hudOverlay(hud)
                }

                if case let .failed(error) = coordinator.state, !error.isSilent {
                    errorOverlay(error)
                }
            }
        }
        .statusBarHidden(true)
        .onAppear {
            baselineBrightness = Double(UIScreen.main.brightness)
            coordinator.play(url: request.url, isLive: request.isLive, profile: request.profile)
            scheduleAutoHide()
        }
        .onDisappear { coordinator.stop() }
        .onReceive(ticker) { _ in refreshProgress() }
    }

    // MARK: - Dérivés d'état

    private var isBuffering: Bool {
        switch coordinator.state {
        case .preparing, .buffering: return true
        default: return false
        }
    }

    private var isPlaying: Bool { coordinator.state == .playing }

    // MARK: - Overlay de contrôles

    private var controlsOverlay: some View {
        VStack(spacing: 0) {
            topBar
            Spacer()
            centerControls
            Spacer()
            if !request.isLive { bottomScrubber }
        }
        .padding()
        .background(
            LinearGradient(colors: [.black.opacity(0.6), .clear, .black.opacity(0.6)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
    }

    private var topBar: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onClose) {
                Image(systemName: "chevron.down")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Fermer le lecteur")

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    if request.isLive { liveBadge }
                    Text(request.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                if let sub = request.subtitle ?? nowNext?.now {
                    Text(sub)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                }
                if let next = nowNext?.next {
                    Text("Ensuite : \(next)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var liveBadge: some View {
        Text("EN DIRECT")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.red, in: RoundedRectangle(cornerRadius: 4))
            .accessibilityLabel("En direct")
    }

    private var centerControls: some View {
        Button {
            togglePlayPause()
        } label: {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 44))
                .foregroundStyle(.white)
                .frame(width: 80, height: 80)
        }
        .accessibilityLabel(isPlaying ? "Pause" : "Lecture")
        .opacity(isBuffering ? 0 : 1)
    }

    private var bottomScrubber: some View {
        HStack(spacing: 10) {
            Text(TimeFormatting.clock(currentTime))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white)
            Slider(
                value: Binding(
                    get: { duration > 0 ? currentTime : 0 },
                    set: { currentTime = $0 }
                ),
                in: 0...max(duration, 1),
                onEditingChanged: { editing in
                    isScrubbing = editing
                    if !editing {
                        coordinator.seek(to: currentTime)
                        scheduleAutoHide()
                    }
                }
            )
            .tint(.orange)
            Text(TimeFormatting.clock(duration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    // MARK: - HUD volume / luminosité

    private func hudOverlay(_ hud: HUD) -> some View {
        let (icon, value): (String, Double) = {
            switch hud {
            case let .volume(v):     return ("speaker.wave.2.fill", v)
            case let .brightness(v): return ("sun.max.fill", v)
            }
        }()
        return VStack(spacing: 10) {
            Image(systemName: icon).font(.title2).foregroundStyle(.white)
            ProgressView(value: value)
                .progressViewStyle(.linear)
                .tint(.white)
                .frame(width: 140)
        }
        .padding(20)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Overlay d'erreur

    private func errorOverlay(_ error: PlaybackError) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text(error.title)
                .font(.headline)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(error.message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
            Button(error.action) { handleErrorAction(error) }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
        }
        .padding(28)
        .frame(maxWidth: 360)
        .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 20))
        .padding()
    }

    private func handleErrorAction(_ error: PlaybackError) {
        switch error.kind {
        case .accessDenied, .schemeRejected, .unsupportedFormat, .unreadableContainer:
            onClose()   // définitif : l'action ramène en arrière
        default:
            coordinator.play(url: request.url, isLive: request.isLive, profile: request.profile)
        }
    }

    // MARK: - Gestes (routés par PlayerGestureArbiter)

    private func gestureLayer(size: CGSize) -> some View {
        let arbiter = PlayerGestureArbiter(isLive: request.isLive)
        return Color.clear
            .contentShape(Rectangle())
            .onTapGesture { toggleControls() }
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in onDragChanged(value, size: size, arbiter: arbiter) }
                    .onEnded { value in onDragEnded(value, size: size, arbiter: arbiter) }
            )
    }

    private func onDragChanged(_ value: DragGesture.Value, size: CGSize,
                               arbiter: PlayerGestureArbiter) {
        let horizontal = abs(value.translation.width) > abs(value.translation.height)
        guard !horizontal else { return }   // l'horizontal (chaîne) est traité à la fin

        if dragSide == nil {
            dragSide = value.startLocation.x < size.width / 2 ? .left : .right
            baselineBrightness = Double(UIScreen.main.brightness)
            baselineVolumeHUD = Double(volume.current)
        }
        guard let side = dragSide else { return }

        let delta = Double(-value.translation.height / max(size.height, 1))   // haut = +
        switch arbiter.resolve(.verticalDrag(side: side, delta: delta)) {
        case let .adjustBrightness(d):
            let v = min(1, max(0, baselineBrightness + d))
            UIScreen.main.brightness = CGFloat(v)
            hud = .brightness(v)
        case let .adjustVolume(d):
            let v = min(1, max(0, baselineVolumeHUD + d))
            volume.set(Float(v))     // MPVolumeView masqué → volume système réel
            hud = .volume(v)
        default:
            break
        }
    }

    private func onDragEnded(_ value: DragGesture.Value, size: CGSize,
                             arbiter: PlayerGestureArbiter) {
        let horizontal = abs(value.translation.width) > abs(value.translation.height)
        if horizontal {
            let delta = Double(value.translation.width / max(size.width, 1))
            if case let .changeChannel(step) = arbiter.resolve(.horizontalDrag(delta: delta)) {
                onChangeChannel(step)
            }
        } else if case let .volume(v) = hud {
            baselineVolumeHUD = v
        }
        dragSide = nil
        // Laisse le HUD un court instant puis l'efface.
        let work = DispatchWorkItem { withAnimation { hud = nil } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    // MARK: - Contrôles : visibilité & lecture

    private func togglePlayPause() {
        if isPlaying { coordinator.pause() } else { coordinator.resume() }
        scheduleAutoHide()
    }

    private func toggleControls() {
        withAnimation { controlsVisible.toggle() }
        if controlsVisible { scheduleAutoHide() }
    }

    private func scheduleAutoHide() {
        hideWorkItem?.cancel()
        guard controlsVisible else { return }
        let work = DispatchWorkItem {
            guard !isScrubbing else { return }
            withAnimation { controlsVisible = false }
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }

    private func refreshProgress() {
        guard !request.isLive, !isScrubbing else { return }
        if let d = coordinator.durationSeconds { duration = d }
        if let t = coordinator.currentTimeSeconds { currentTime = t }
    }
}
