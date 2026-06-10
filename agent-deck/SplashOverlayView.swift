import AppKit
import Lottie
import SwiftUI

/// Plays the bundled brand splash animation once (paper-plane fleet + wordmark
/// type-on) over a transparent background, holding the final lockup frame.
/// Hosted inside `AppInitialLoadOverlay`, which owns the backdrop and dismissal.
struct SplashAnimationView: NSViewRepresentable {
    func makeNSView(context: Context) -> LottieAnimationView {
        let animation = LottieAnimation.named("agent-deck-splash", subdirectory: "Animations")
            ?? LottieAnimation.named("agent-deck-splash")
        let view = LottieAnimationView(animation: animation)
        view.contentMode = .scaleAspectFit
        view.loopMode = .playOnce
        view.play()
        return view
    }

    func updateNSView(_ nsView: LottieAnimationView, context: Context) {}
}
