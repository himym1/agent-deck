import AppKit

/// Self-contained visual harness for `PiAgentNativeBubbleView`, so the native
/// transcript bubbles can be verified without loading a real project/session
/// (which requires Documents access). Renders sample reply / thinking / question
/// bubbles into a borderless window pinned to the screen's top-left corner.
///
/// Enable with: `defaults write streetcoding.agent-deck NativeBubblePreview -bool YES`
/// Disable with the same key set to NO. Off by default; no effect in normal use.
@MainActor
enum NativeBubblePreviewDebug {
    private static var window: NSWindow?

    static func showIfEnabled() {
        guard UserDefaults.standard.bool(forKey: "NativeBubblePreview") else { return }
        // Let the app finish launching first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { show() }
    }

    private static func show() {
        let rowWidth: CGFloat = 680
        let payloads: [NativeBubblePayload] = [
            NativeBubblePayload(
                role: .assistant, headerTitle: "Coding Agent", iconSymbol: nil,
                markdownSource: "Here is a **reply** with `inline code`, a [link](https://x), and a list:\n- first item\n- second item\n\nAnd a short closing line.",
                bodyPrefix: nil, copyText: "x", copySide: .trailing, isThreadChild: true
            ),
            NativeBubblePayload(
                role: .thinking, headerTitle: "Thinking", iconSymbol: "brain.head.profile",
                markdownSource: "Considering the options and weighing trade-offs before answering.",
                bodyPrefix: "Reasoning", copyText: "x", copySide: .trailing, isThreadChild: true
            ),
            NativeBubblePayload(
                role: .user, headerTitle: "You", iconSymbol: "person.crop.circle",
                markdownSource: "bi", bodyPrefix: nil, copyText: "bi", copySide: .leading,
                isThreadChild: false, isUserHugged: true,
                fork: ForkModel(onForkSession: {}, agentOptions: [
                    ForkAgentOption(title: "Coder", isDisabled: false, action: {}),
                    ForkAgentOption(title: "Reviewer", isDisabled: true, action: {})
                ])
            ),
            NativeBubblePayload(
                role: .user, headerTitle: "You", iconSymbol: "person.crop.circle",
                markdownSource: "Can you refactor the transcript rendering to be fully native and make sure scrolling is smooth across long sessions?",
                bodyPrefix: nil, copyText: "x", copySide: .leading,
                isThreadChild: false, isUserHugged: true,
                fork: ForkModel(onForkSession: {}, agentOptions: [])
            )
        ]

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 0, bottom: 16, right: 0)

        var bubbles: [PiAgentNativeBubbleView] = []
        for payload in payloads {
            let bubble = PiAgentNativeBubbleView()
            bubble.translatesAutoresizingMaskIntoConstraints = false
            bubble.configure(payload: payload, width: rowWidth)
            stack.addArrangedSubview(bubble)
            bubble.widthAnchor.constraint(equalToConstant: rowWidth).isActive = true
            bubble.heightAnchor.constraint(equalToConstant: bubble.measuredHeight(forWidth: rowWidth)).isActive = true
            bubbles.append(bubble)
        }

        let content = NSView()
        content.wantsLayer = true
        // Match the dark transcript backdrop so tints/text/glass read correctly.
        content.layer?.backgroundColor = CGColor(srgbRed: 0.12, green: 0.12, blue: 0.13, alpha: 1)
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: rowWidth + 24, height: 700),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        win.title = "Native Bubble Preview"
        win.appearance = NSAppearance(named: .darkAqua)
        win.contentView = content
        win.setFrameTopLeftPoint(NSPoint(x: 40, y: (NSScreen.main?.frame.height ?? 900) - 40))
        win.makeKeyAndOrderFront(nil)
        win.level = .floating
        window = win

        // Reveal the hover buttons so they're visible in a static screenshot.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            for bubble in bubbles { bubble.previewRevealButtons() }
        }
    }
}
