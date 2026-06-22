import AppKit
import SwiftUI
import XCTest
@testable import agent_deck

@MainActor
final class PiAgentUIRequestSheetLayoutTests: XCTestCase {
    func testNativeAskChoiceSheetFitsWithinBoundedGlassSheet() {
        let request = makeNativeAskRequest()
        let host = NSHostingView(rootView: PiAgentUIRequestSheet(
            request: request,
            onSubmitValue: { _ in },
            onSubmitFreeform: { _, _ in },
            onConfirm: { _ in },
            onCancel: {}
        ))

        host.frame = NSRect(x: 0, y: 0, width: 1_120, height: 860)
        host.layoutSubtreeIfNeeded()

        let size = host.fittingSize
        XCTAssertGreaterThan(size.width, 700)
        XCTAssertLessThanOrEqual(size.width, 1_160)
        XCTAssertLessThanOrEqual(size.height, 900)
        XCTAssertTrue(size.width.isFinite)
        XCTAssertTrue(size.height.isFinite)
    }

    func testNativeAskFreeformPageFitsWithinBoundedGlassSheet() {
        let request = makeNativeAskRequest()
        let host = NSHostingView(rootView: PiAgentUIRequestSheet(
            request: request,
            onSubmitValue: { _ in },
            onSubmitFreeform: { _, _ in },
            onConfirm: { _ in },
            onCancel: {},
            initiallyComposingFreeform: true
        ))

        host.frame = NSRect(x: 0, y: 0, width: 1_120, height: 860)
        host.layoutSubtreeIfNeeded()

        let size = host.fittingSize
        XCTAssertGreaterThan(size.width, 700)
        XCTAssertLessThanOrEqual(size.width, 1_160)
        XCTAssertLessThanOrEqual(size.height, 900)
        XCTAssertTrue(size.width.isFinite)
        XCTAssertTrue(size.height.isFinite)
    }

    private func makeNativeAskRequest() -> PiAgentUIRequest {
        PiAgentUIRequest(
            id: "layout-smoke",
            sessionID: UUID(),
            method: .select,
            title: "For Milestone 0, how should existing `.chain.md` files be handled while retiring Chains? My recommendation is a one-release diagnostic warning: it is cautious, avoids silent surprises if someone has local unreleased files, and does not over-invest in migration.",
            message: "I read docs/loop-plan and inventoried current chain references. Chains appear only as unreleased/stale documentation plus PiScanner exclusions that prevent `.chain.md` files from being parsed as prompts/agents. There is no current `ChainPersistence.swift` or user-facing chain UI in the source tree. The loop plan leaves `.chain.md` handling open.",
            options: [
                "Diagnostic warning (recommended)",
                "Ignore silently",
                "Migration support"
            ],
            optionDescriptions: [
                "Diagnostic warning (recommended)": "Keep ignoring `.chain.md` as active resources, but surface a scan warning explaining Chains are retired/unreleased and not loaded.",
                "Ignore silently": "Continue excluding `.chain.md` from resources without any user-visible warning.",
                "Migration support": "Add conversion from `.chain.md` to loop definitions; larger and likely premature unless real user data exists."
            ],
            placeholder: nil,
            prefill: nil,
            allowsFreeform: true,
            allowsComment: true,
            responseFormat: .nativeAsk
        )
    }
}
