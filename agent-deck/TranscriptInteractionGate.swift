import QuartzCore

/// Tiny shared signal so non-UI services can tell whether the user is actively
/// scrolling the transcript and defer main-thread work that would otherwise
/// land as a mid-gesture stall.
///
/// The background project rescan reassigns observable state in
/// `applyRefreshSnapshot`, which re-evaluates the whole screen body (the
/// transcript's `itemsBuild` + `updateNSView`). When that lands while a scroll
/// gesture is live it drops frames. The transcript's scroll observers stamp
/// `noteInteraction()`; the file-watch refresh reads `isInteractingRecently`
/// and re-arms instead of firing until the gesture settles.
@MainActor
enum TranscriptInteractionGate {
    private static var lastInteraction: CFTimeInterval = 0
    /// Window after the last scroll tick during which the user still counts as
    /// interacting. The bounds observer ticks roughly once per frame while a
    /// gesture is live, so any in-progress scroll keeps this fresh; the tail
    /// covers inertial settle and the gap between discrete mouse-wheel notches.
    private static let activeWindow: CFTimeInterval = 0.25

    static func noteInteraction() { lastInteraction = CACurrentMediaTime() }

    static var isInteractingRecently: Bool {
        CACurrentMediaTime() - lastInteraction < activeWindow
    }

    // MARK: - Streaming stamp
    //
    // Mirrors the profiler's streaming-activity tracking so non-UI services
    // (file-watch refresh) can defer main-thread work during live generation
    // without grabbing the profiler instance. The Coordinator stamps this
    // alongside `profiler.noteStreamingActivity()` in `apply()`.
    private static var lastStreaming: CFTimeInterval = 0
    /// Matches the profiler's streaming recency window (~600ms) so the gate
    /// and the profiler agree on whether a stream is in flight.
    private static let streamingWindow: CFTimeInterval = 0.6

    static func noteStreaming() { lastStreaming = CACurrentMediaTime() }

    static var isStreamingRecently: Bool {
        CACurrentMediaTime() - lastStreaming < streamingWindow
    }
}
