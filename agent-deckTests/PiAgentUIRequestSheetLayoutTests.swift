import AppKit
import SwiftUI
import XCTest
@testable import agent_deck

@MainActor
final class PiAgentUIRequestSheetLayoutTests: XCTestCase {
    func testNativeAskSingleSelectWithOptionsAndFreeformUsesStableCanonicalSheetSize() {
        assertStableCanonicalSheetSize(for: makeNativeAskSelectionRequest(id: "native-single-select"))
    }

    func testNativeAskInitiallyComposingFreeformUsesStableCanonicalSheetSize() {
        assertStableCanonicalSheetSize(
            for: makeNativeAskSelectionRequest(id: "native-initial-freeform", prefill: "Existing custom response"),
            initiallyComposingFreeform: true
        )
    }

    func testNativeAskMultiSelectUsesStableCanonicalSheetSize() {
        assertStableCanonicalSheetSize(for: makeRequest(
            id: "native-multi-select",
            method: .multiSelect,
            title: "Which follow-up checks should Pi run before continuing?",
            message: "Pick every validation step that should be included in the next turn.",
            options: ["Run focused tests", "Build Debug app", "Inspect generated logs"],
            optionDescriptions: [
                "Run focused tests": "Run only the tests that exercise the changed Ask User sheet behavior.",
                "Build Debug app": "Compile the app target to catch SwiftUI or linking regressions.",
                "Inspect generated logs": "Open the generated result bundle and inspect any warnings."
            ],
            allowsFreeform: false,
            responseFormat: .nativeAsk
        ))
    }

    func testConfirmUsesStableCanonicalSheetSize() {
        assertStableCanonicalSheetSize(for: makeRequest(
            id: "confirm",
            method: .confirm,
            title: "Should Pi continue with the proposed change?",
            message: "Pi is asking for explicit confirmation before it edits project files.",
            responseFormat: .plain
        ))
    }

    func testPlainInputUsesStableCanonicalSheetSize() {
        assertStableCanonicalSheetSize(for: makeRequest(
            id: "plain-input",
            method: .input,
            title: "What branch name should Pi use?",
            message: "Enter a short branch name for the implementation.",
            placeholder: "feature/ask-user-layout",
            responseFormat: .plain
        ))
    }

    func testEditorInputUsesStableCanonicalSheetSize() {
        assertStableCanonicalSheetSize(for: makeRequest(
            id: "editor-input",
            method: .editor,
            title: "Describe the release note Pi should draft.",
            message: "Use the larger editor input for a multi-line response.",
            placeholder: "Release note details",
            prefill: "Start with the user-visible Ask User sheet behavior.",
            responseFormat: .plain
        ))
    }

    func testSelectWithNoOptionsUsesStableCanonicalSheetSize() {
        assertStableCanonicalSheetSize(for: makeRequest(
            id: "select-no-options",
            method: .select,
            title: "Pi requested a selection but returned no choices.",
            message: "The sheet should render the empty-options state without collapsing or growing.",
            options: [],
            responseFormat: .plain
        ))
    }

    func testMultiSelectWithEmptyOptionsUsesStableCanonicalSheetSize() {
        assertStableCanonicalSheetSize(for: makeRequest(
            id: "multi-empty-options",
            method: .multiSelect,
            title: "Pi requested multiple selections but returned an empty choice list.",
            message: "The sheet should use the same stable shell for empty multi-select requests.",
            options: [],
            responseFormat: .nativeAsk
        ))
    }

    func testLongOptionDescriptionsUseStableCanonicalSheetSize() {
        let longDescription = String(repeating: "This option has a deliberately long explanatory paragraph so the option row must wrap across multiple lines without forcing the fitted sheet taller than its canonical height. ", count: 5)
        assertStableCanonicalSheetSize(for: makeRequest(
            id: "long-option-descriptions",
            method: .select,
            title: "Choose the migration strategy with detailed tradeoffs.",
            message: "Each choice includes a long explanation that should remain inside the scrollable body.",
            options: ["Conservative", "Balanced", "Aggressive"],
            optionDescriptions: [
                "Conservative": longDescription,
                "Balanced": longDescription,
                "Aggressive": longDescription
            ],
            allowsFreeform: true,
            responseFormat: .nativeAsk
        ))
    }

    func testManyOptionsUseBodyScrollAndStableCanonicalSheetSize() {
        let options = (1...28).map { "Validation option \($0)" }
        let descriptions = Dictionary(uniqueKeysWithValues: options.map { option in
            (option, "A concise description for \(option) that ensures each row has normal secondary text.")
        })

        assertStableCanonicalSheetSize(for: makeRequest(
            id: "many-options-scroll",
            method: .multiSelect,
            title: "Select all validations Pi should run.",
            message: "This request intentionally has enough choices to require the sheet body to scroll instead of expanding the sheet.",
            options: options,
            optionDescriptions: descriptions,
            responseFormat: .plain
        ))
    }

    private func assertStableCanonicalSheetSize(
        for request: PiAgentUIRequest,
        initiallyComposingFreeform: Bool = false,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let host = NSHostingView(rootView: PiAgentUIRequestSheet(
            request: request,
            onSubmitValue: { _ in },
            onSubmitFreeform: { _, _ in },
            onConfirm: { _ in },
            onCancel: {},
            initiallyComposingFreeform: initiallyComposingFreeform
        ))

        host.frame = NSRect(x: 0, y: 0, width: 1_120, height: 860)
        host.layoutSubtreeIfNeeded()

        let size = host.fittingSize
        XCTAssertGreaterThanOrEqual(size.width, 800, file: file, line: line)
        XCTAssertLessThanOrEqual(size.width, 840, file: file, line: line)
        XCTAssertGreaterThanOrEqual(size.height, 580, file: file, line: line)
        XCTAssertLessThanOrEqual(size.height, 620, file: file, line: line)
        XCTAssertTrue(size.width.isFinite, file: file, line: line)
        XCTAssertTrue(size.height.isFinite, file: file, line: line)
    }

    private func makeNativeAskSelectionRequest(
        id: String = "native-single-select",
        prefill: String? = nil
    ) -> PiAgentUIRequest {
        makeRequest(
            id: id,
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
            prefill: prefill,
            allowsFreeform: true,
            allowsComment: true,
            responseFormat: .nativeAsk
        )
    }

    private func makeRequest(
        id: String,
        method: PiAgentUIRequest.Method,
        title: String,
        message: String? = nil,
        options: [String] = [],
        optionDescriptions: [String: String] = [:],
        placeholder: String? = nil,
        prefill: String? = nil,
        allowsFreeform: Bool = false,
        allowsComment: Bool = false,
        responseFormat: PiAgentUIRequest.ResponseFormat = .plain
    ) -> PiAgentUIRequest {
        PiAgentUIRequest(
            id: id,
            sessionID: UUID(),
            method: method,
            title: title,
            message: message,
            options: options,
            optionDescriptions: optionDescriptions,
            placeholder: placeholder,
            prefill: prefill,
            allowsFreeform: allowsFreeform,
            allowsComment: allowsComment,
            responseFormat: responseFormat
        )
    }
}
