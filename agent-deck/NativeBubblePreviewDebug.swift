import AppKit
import SwiftUI

/// Self-contained visual harness for `PiAgentNativeBubbleView`, so the native
/// transcript bubbles can be verified — and pixel-compared against the hosted
/// SwiftUI rows — without loading a real project/session (which requires
/// Documents access).
///
/// It stacks, at one fixed row width with a red guide line at content x=0:
///   1. the NATIVE assistant reply bubble (the `.bubble` render path),
///   2. the HOSTED assistant card, wrapped exactly as the real reply row does
///      (`card.frame(maxWidth: replyCap, alignment: .leading)` + trailing
///      Spacer), pinned leading=0 like the production hosted cell — so any
///      left-edge offset between native and hosted is directly measurable,
///   3. the NATIVE question bubble (right-aligned hugged), to verify it never
///      lands on the left.
///
/// Enable with: `defaults write streetcoding.agent-deck NativeBubblePreview -bool YES`
/// Off by default; no effect in normal use.
@MainActor
enum NativeBubblePreviewDebug {
    private static var window: NSWindow?

    /// The full row width the production transcript hands a cell (column width).
    private static let rowWidth: CGFloat = 900

    static func showIfEnabled() {
        guard UserDefaults.standard.bool(forKey: "NativeBubblePreview") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { show() }
    }

    private static func show() {
        let assistantText = "Let me explore the codebase to find where these Pi icons are defined and what colors they use."
        let assistantEntry = PiAgentTranscriptEntry(
            sessionID: UUID(), role: .assistant, title: "Coding Agent", text: assistantText
        )

        // (1) Native assistant reply bubble.
        let nativeReply = PiAgentNativeBubbleView()
        nativeReply.configure(payload: NativeBubblePayload(
            role: .assistant, headerTitle: "Coding Agent", iconSymbol: nil,
            markdownSource: assistantText, bodyPrefix: nil,
            copyText: assistantText, copySide: .trailing, isThreadChild: true
        ), width: rowWidth)

        // (2) Hosted assistant card, wrapped like the production reply row.
        let hostedReply = NSHostingView(rootView: AnyView(
            HStack(spacing: 0) {
                PiAgentTranscriptCard(entry: assistantEntry, style: .threadChild)
                    .frame(maxWidth: PiAgentBubbleWidth.replyCap(for: rowWidth), alignment: .leading)
                Spacer(minLength: 60)
            }
            .frame(width: rowWidth, alignment: .topLeading)
            .environment(\.transcriptContentWidth, rowWidth)
        ))

        // (2b) Hosted tool-group row — the user's stated alignment reference.
        // Rendered through the exact production path (PiAgentTranscriptThreadCard
        // in `.child(.toolGroup)` mode), wrapped like the real reply row.
        let toolEntry = PiAgentTranscriptEntry(
            sessionID: UUID(), role: .tool, title: "Tool: shell", text: "ls -la\nrg \"pi\""
        )
        let questionEntry = PiAgentTranscriptEntry(
            sessionID: UUID(), role: .user, title: "You", text: "hello"
        )
        let toolGroup = PiAgentThreadToolGroup(
            id: UUID(), entries: [toolEntry],
            activities: PiAgentTranscriptActivity.make(from: [toolEntry])
        )
        let toolThread = PiAgentTranscriptThread(
            id: UUID(), question: questionEntry, steeringMessages: [], thinkingParts: [],
            assistantMessages: [], activities: toolGroup.activities, statuses: [], errors: [],
            children: [.toolGroup(toolGroup)]
        )
        let hostedTool = NSHostingView(rootView: AnyView(
            HStack(spacing: 0) {
                PiAgentTranscriptThreadCard(
                    thread: toolThread,
                    visibility: PiAgentTranscriptVisibilitySettings(),
                    skills: [],
                    projectPath: nil,
                    nativeSubagentRunsByID: [:],
                    nativeSubagentCard: { _ in fatalError("no subagent in preview") },
                    renderMode: .child(.toolGroup(toolGroup))
                )
                .frame(maxWidth: PiAgentBubbleWidth.replyCap(for: rowWidth), alignment: .leading)
                Spacer(minLength: 60)
            }
            .frame(width: rowWidth, alignment: .topLeading)
            .environment(\.transcriptContentWidth, rowWidth)
        ))

        // (3) Native question bubble (must stay right-aligned).
        let nativeQuestion = PiAgentNativeBubbleView()
        nativeQuestion.configure(payload: NativeBubblePayload(
            role: .user, headerTitle: "You", iconSymbol: "person.crop.circle",
            markdownSource: "hello", bodyPrefix: nil, copyText: "hello",
            copySide: .leading, isThreadChild: false, isUserHugged: true,
            fork: ForkModel(onForkSession: {}, agentOptions: [])
        ), width: rowWidth)

        let rows: [(String, NSView, CGFloat)] = [
            ("NATIVE assistant reply", nativeReply, nativeReply.measuredHeight(forWidth: rowWidth)),
            ("HOSTED assistant card", hostedReply, 90),
            ("HOSTED tool group (reference)", hostedTool, 90),
            ("NATIVE question (right-aligned)", nativeQuestion, nativeQuestion.measuredHeight(forWidth: rowWidth))
        ]

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 28
        stack.translatesAutoresizingMaskIntoConstraints = false

        for (title, view, height) in rows {
            let label = NSTextField(labelWithString: title)
            label.font = NSFont.systemFont(ofSize: 10, weight: .bold)
            label.textColor = .systemRed
            stack.addArrangedSubview(label)
            view.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(view)
            view.widthAnchor.constraint(equalToConstant: rowWidth).isActive = true
            view.heightAnchor.constraint(equalToConstant: height).isActive = true
        }

        let content = NSView()
        content.wantsLayer = true
        content.layer?.backgroundColor = CGColor(srgbRed: 0.12, green: 0.12, blue: 0.13, alpha: 1)
        content.addSubview(stack)
        let contentLeading: CGFloat = 16
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: contentLeading),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16)
        ])

        // Red guide line at content x=0 (the leading edge every row is pinned to).
        let guide = NSView()
        guide.wantsLayer = true
        guide.layer?.backgroundColor = NSColor.systemRed.cgColor
        guide.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(guide)
        NSLayoutConstraint.activate([
            guide.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: contentLeading),
            guide.widthAnchor.constraint(equalToConstant: 1),
            guide.topAnchor.constraint(equalTo: content.topAnchor),
            guide.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: rowWidth + 32, height: 560),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        win.title = "Native Bubble Preview"
        win.appearance = NSAppearance(named: .darkAqua)
        win.contentView = content
        win.setFrameTopLeftPoint(NSPoint(x: 40, y: (NSScreen.main?.frame.height ?? 900) - 40))
        win.makeKeyAndOrderFront(nil)
        win.level = .floating
        window = win

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            nativeReply.previewRevealButtons()
            nativeQuestion.previewRevealButtons()
        }
    }
}
