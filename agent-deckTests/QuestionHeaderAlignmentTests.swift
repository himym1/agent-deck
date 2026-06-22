import AppKit
import XCTest
@testable import agent_deck

/// Regression tests for the "You header sits above the person symbol on the
/// first paint of a chip-bearing question card" bug.
///
/// Root cause: `PiAgentNativeQuestionView.headerLabel` had only a `centerY` pin
/// to the icon and relied on its intrinsic content size for height. AppKit's
/// constraint solver does not always honor that intrinsic on the FIRST layout
/// pass of a freshly-configured card — it can transiently assign the label an
/// over-tall frame (observed ~84pt for a ~16pt label). NSTextField draws its
/// text at the TOP of an over-tall frame, so "You" paints high above the icon
/// until a later relayout (e.g. switching sessions away and back) collapses the
/// frame and re-centers the text. The fix pins the label's height explicitly so
/// it is deterministic from the first solve.
///
/// These tests drive the production cell flow (configure → settle → layout)
/// offscreen and read the private view tree by traversal, so no production code
/// has to change to observe the geometry.
@MainActor
final class QuestionHeaderAlignmentTests: XCTestCase {

    private let rowWidth: CGFloat = 900

    /// A question card with a body + a single file-attachment chip — the
    /// "new session with an attachment" shape that triggered the misalignment.
    private func attachmentPayload() -> NativeQuestionPayload {
        NativeQuestionPayload(
            markdownSource: "Here is a file to look at.",
            chips: [
                NativeQuestionChip(
                    kind: .file,
                    systemImage: "doc.text",
                    label: "README.md",
                    attachment: .file(name: "README.md", path: nil)
                )
            ],
            copyText: "Here is a file to look at.",
            fork: nil,
            headerTitle: "You",
            headerIcon: "person.fill",
            chipsNaturalWidth: 120,
            identity: 1
        )
    }

    /// cardView is the rounded direct subview; the icon is its NSImageView and
    /// the "You" title is its single direct NSTextField.
    private func headerLabel(in view: PiAgentNativeQuestionView) -> NSTextField? {
        let cardView = view.subviews.first(where: { ($0.layer?.cornerRadius ?? 0) > 0 })
        return cardView?.subviews.first(where: { $0 is NSTextField }) as? NSTextField
    }

    private func iconView(in view: PiAgentNativeQuestionView) -> NSImageView? {
        let cardView = view.subviews.first(where: { ($0.layer?.cornerRadius ?? 0) > 0 })
        return cardView?.subviews.first(where: { $0 is NSImageView }) as? NSImageView
    }

    /// The production cell flow (configure → settle → layout) plus the recursive
    /// frame read whose access pattern reliably surfaces the transient over-tall
    /// label frame. Returns the header label and icon AFTER that read.
    private func configureHostAndSweep() -> (header: NSTextField, icon: NSImageView) {
        let measure = PiAgentNativeQuestionView()
        measure.configure(payload: attachmentPayload(), width: rowWidth)
        let measured = measure.measuredHeight(forWidth: rowWidth)

        let view = PiAgentNativeQuestionView()
        view.configure(payload: attachmentPayload(), width: rowWidth)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: rowWidth, height: max(measured, 1)),
            styleMask: [.borderless], backing: .buffered, defer: false)
        let host = NSView(frame: NSRect(x: 0, y: 0, width: rowWidth, height: max(measured, 1)))
        window.contentView = host
        window.orderFrontRegardless()
        host.addSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: host.topAnchor),
            view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            view.widthAnchor.constraint(equalToConstant: rowWidth),
            view.heightAnchor.constraint(equalToConstant: measured)
        ])
        view.settleLayoutImmediately()
        host.layoutSubtreeIfNeeded()
        // Recursive frame read — this access pattern is what exposes the
        // transient ambiguous solve on an unfixed label.
        func sweep(_ v: NSView) {
            _ = "\(type(of: v)) \(v.frame)"
            for s in v.subviews { sweep(s) }
        }
        sweep(view)
        guard let header = headerLabel(in: view), let icon = iconView(in: view) else {
            preconditionFailure("Could not locate headerLabel/iconView in the view tree")
        }
        return (header, icon)
    }

    /// The header label's height must be the deterministic icon-box height, never
    /// the transient over-tall value (~84pt) the solver produced before the fix.
    /// This is the direct guard against the regression.
    func testHeaderLabelHeightIsDeterministic() {
        for _ in 0..<10 {
            let (header, _) = configureHostAndSweep()
            XCTAssertEqual(header.frame.height, NativeTranscriptFont.headerIconSize, accuracy: 1.0,
                "headerLabel height drifted to \(header.frame.height) — the ambiguous over-tall " +
                "frame that paints 'You' above the icon has returned.")
        }
    }

    /// The "You" text frame must be vertically centered on the icon glyph on the
    /// very first configured layout — not only after a session-switch relayout.
    func testHeaderCenteredToIconOnFirstLayout() {
        let (header, icon) = configureHostAndSweep()
        // The icon glyph is the inner `_NSImageViewSimpleImageView`; center on
        // that (the iconView frame carries the symbol's alignment margins).
        let glyph = icon.subviews.first
        let glyphMidY = (glyph?.frame.midY ?? icon.frame.midY) + icon.frame.minY
        let drift = abs(header.frame.midY - glyphMidY)
        XCTAssertLessThan(drift, 2.0,
            "'You' header center (y=\(header.frame.midY)) is not vertically centered on the " +
            "icon glyph (y=\(glyphMidY)); drift=\(drift).")
    }

    /// Sanity: the measured height must still account for the chip row so the
    /// card isn't cropped (the chip-row-height-before-first-paint invariant).
    func testMeasuredHeightIncludesChipRow() {
        let withChip = PiAgentNativeQuestionView()
        withChip.configure(payload: attachmentPayload(), width: rowWidth)
        let chipH = withChip.measuredHeight(forWidth: rowWidth)

        var noChipPayload = attachmentPayload()
        noChipPayload.chips = []
        noChipPayload.identity = 2
        let noChip = PiAgentNativeQuestionView()
        noChip.configure(payload: noChipPayload, width: rowWidth)
        let plainH = noChip.measuredHeight(forWidth: rowWidth)

        XCTAssertGreaterThan(chipH, plainH + 20,
            "Measured height must include the chip row + divider; chipH=\(chipH) plainH=\(plainH)")
    }
}
