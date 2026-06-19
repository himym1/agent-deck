import AppKit
import XCTest
@testable import agent_deck

/// Regression tests for the streaming-transcript "wobble" — the bottom bubble
/// jittering up/down as new tokens arrive. The root triggers are:
///   1. The markdown container bailing from its incremental reconcile path to a
///      full rebuild, which resets `lastFullLayoutWidth` and forces a cold
///      double-pass measure on the next tick.
///   2. A measured height coming back slightly shorter than the last tile due to
///      TextKit/measurement noise, which the table then re-tiles upward.
@MainActor
final class MarkdownStreamingStabilityTests: XCTestCase {

    private func runMainLoop(iterations: Int = 4, delay: TimeInterval = 0.02) {
        for _ in 0..<iterations {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(delay))
        }
    }

    /// Aggressive cleanup to keep XCTest's memory checker happy: cancel any
    /// in-flight applier work, pump the runloop to drain autorelease pools, and
    /// explicitly keep the container alive until the pump finishes.
    private func drainAndRelease(container: NativeMarkdownTextContainer, applier: MarkdownSourceApplier) {
        applier.cancel()
        container.dismantle()
        runMainLoop(iterations: 6, delay: 0.02)
        withExtendedLifetime(container) {}
    }

    /// A fresh container should build from scratch; subsequent streaming growth
    /// should reconcile in place rather than force a full rebuild.
    func testStreamingGrowthReconcilesWithoutFullRebuild() throws {
        let container = NativeMarkdownTextContainer()
        let applier = MarkdownSourceApplier()
        defer { drainAndRelease(container: container, applier: applier) }

        let seq0 = NativeMarkdownTextContainer.configureSeq

        applier.apply(source: "Hello", to: container)
        runMainLoop()
        XCTAssertTrue(
            container.lastConfigureWasRebuildInstance,
            "first appearance should be a full build"
        )
        let seq1 = NativeMarkdownTextContainer.configureSeq
        XCTAssertGreaterThan(seq1, seq0, "configureSeq should advance on first build")

        // Typical streaming: the same paragraph grows by appending text.
        applier.apply(source: "Hello world", to: container)
        runMainLoop()
        XCTAssertFalse(
            container.lastConfigureWasRebuildInstance,
            "streaming growth should take the incremental reconcile path"
        )

        // The old `frontmatterOrViewCount` bail would have forced a full rebuild here,
        // resetting `lastFullLayoutWidth` and causing the next measure to take the
        // cold double-pass. The fix keeps the reconcile path open whenever the
        // frontmatter is unchanged, even if the arranged-subview count has drifted.
        applier.apply(source: "Hello world, this is streaming", to: container)
        runMainLoop()
        XCTAssertFalse(
            container.lastConfigureWasRebuildInstance,
            "continued streaming growth should still reconcile"
        )
    }

    /// Structural changes that do NOT touch frontmatter (e.g., a new list item
    /// appearing, a code fence opening, the balancer stripping a trailing marker
    /// and changing block count) should still reconcile, not rebuild.
    func testStructuralChangesReconcileWithoutRebuild() throws {
        let container = NativeMarkdownTextContainer()
        let applier = MarkdownSourceApplier()
        defer { drainAndRelease(container: container, applier: applier) }

        applier.apply(source: "Plain paragraph.\n\n- first item", to: container)
        runMainLoop()
        XCTAssertTrue(container.lastConfigureWasRebuildInstance, "first build")

        // Append a second list item: block count changes, frontmatter unchanged.
        applier.apply(source: "Plain paragraph.\n\n- first item\n- second item", to: container)
        runMainLoop()
        XCTAssertFalse(
            container.lastConfigureWasRebuildInstance,
            "adding a list item should reconcile"
        )

        // Close a code fence: a new code block appears.
        applier.apply(
            source: "Plain paragraph.\n\n```swift\nlet x = 1\n```",
            to: container
        )
        runMainLoop()
        XCTAssertFalse(
            container.lastConfigureWasRebuildInstance,
            "opening a code fence should reconcile"
        )
    }
}
