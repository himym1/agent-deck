import AppKit
import SwiftUI

// Native (pure AppKit) single-run subagent ("Deck agent") card. This is the
// dominant scroll-hang source in subagent-heavy sessions: hosted, its markdown
// task preview rebuilt its whole NSTextView tree (inside an NSHostingView, with
// SwiftUI's sizeThatFits machinery on top) every scroll vend. Native, the card
// reuses ONE markdown container across vends and only rebuilds on content change.
//
// Parallel-mode runs (a grid of child tiles) still render hosted for now; this
// covers the single-agent case. Mirrors PiNativeSubagentRunCard's `else` branch.

// MARK: - Payload (computed in the items pass; the view is a dumb renderer)

struct NativeSubagentCardPayload {
    var agentName: String
    var shortRunID: String
    var fullRunID: String
    var statusText: String
    var statusColor: NSColor
    var isActive: Bool
    var avatarURL: URL?
    var task: String
    var metrics: [Metric]
    var showGraph: Bool
    var canOpenSystemPrompt: Bool
    var systemPromptText: () -> String
    var detailRows: [(String, String)]
    var canReveal: Bool
    // Actions
    var onStop: () -> Void
    var onTranscript: () -> Void
    var onReveal: () -> Void
    var onGraph: () -> Void

    struct Metric { var icon: String; var text: String }
}

extension NativeSubagentCardPayload {
    /// Build the single-run payload from a run record. Mirrors PiNativeSubagentRunCard's
    /// computed vars (status color, compact metadata, detail rows, artifact checks).
    @MainActor
    static func make(
        run: PiSubagentRunRecord,
        imageStore: AgentImageStore,
        onStop: @escaping () -> Void,
        onTranscript: @escaping () -> Void,
        onReveal: @escaping () -> Void,
        onGraph: @escaping () -> Void
    ) -> NativeSubagentCardPayload {
        let artifactDir = run.child?.artifactDirectory ?? run.artifactDirectory
        let sysPromptURL = URL(fileURLWithPath: artifactDir).appendingPathComponent("final-system-prompt.md")
        let canOpenSysPrompt = FileManager.default.fileExists(atPath: sysPromptURL.path)

        let duration = run.child?.durationMs ?? run.durationMs
        let tokens: Int? = run.child?.totalTokens ?? {
            let t = run.children?.compactMap(\.totalTokens) ?? []
            return t.isEmpty ? nil : t.reduce(0, +)
        }()
        let tools: Int? = run.child?.toolCount ?? {
            let c = run.children?.compactMap(\.toolCount) ?? []
            return c.isEmpty ? nil : c.reduce(0, +)
        }()
        let model = nonEmpty(run.model ?? run.child?.model ?? run.children?.compactMap(\.model).first)
        let thinking = nonEmpty(run.thinking)

        var metrics: [Metric] = []
        if let duration { metrics.append(.init(icon: "timer", text: formattedDuration(duration))) }
        if let tokens { metrics.append(.init(icon: "tugriksign.circle", text: compactNumber(tokens))) }
        if let tools { metrics.append(.init(icon: "wrench.and.screwdriver", text: "\(tools)")) }
        if let model { metrics.append(.init(icon: "cpu", text: model)) }
        if let thinking { metrics.append(.init(icon: "brain.head.profile", text: thinking)) }

        var detailRows: [(String, String)] = [("Deck agent ID", run.id.uuidString)]
        if let duration { detailRows.append(("Duration", formattedDuration(duration))) }
        if let tokens { detailRows.append(("Tokens", compactNumber(tokens))) }
        if let tools { detailRows.append(("Tools", "\(tools)")) }
        if let model { detailRows.append(("Model", model)) }
        if let thinking { detailRows.append(("Thinking", thinking)) }
        if let outcome = run.expectedOutcome {
            detailRows.append(("Outcome", outcome.displayName + (run.requestedOutputPath.map { " · \($0)" } ?? "")))
        }
        if let reads = run.readFirstPaths, !reads.isEmpty {
            detailRows.append(("Read first", reads.joined(separator: ", ")))
        }
        if run.isWorktreeIsolated == true {
            detailRows.append(("Worktree status", (run.worktreeStatus ?? .active).rawValue))
        }

        return NativeSubagentCardPayload(
            agentName: run.agentName,
            shortRunID: String(run.id.uuidString.prefix(8)),
            fullRunID: run.id.uuidString,
            statusText: run.status.rawValue.capitalized,
            statusColor: statusColor(run.status),
            isActive: run.status.isActive,
            avatarURL: imageStore.imageURL(for: run.agentName),
            task: run.task,
            metrics: metrics,
            showGraph: run.children?.isEmpty == false,
            canOpenSystemPrompt: canOpenSysPrompt,
            systemPromptText: {
                (try? String(contentsOf: sysPromptURL, encoding: .utf8)) ?? "System prompt unavailable."
            },
            detailRows: detailRows,
            canReveal: !run.artifactDirectory.isEmpty,
            onStop: onStop,
            onTranscript: onTranscript,
            onReveal: onReveal,
            onGraph: onGraph
        )
    }

    /// True when this run renders as a parallel grid (handled by the hosted card),
    /// false for the single-agent card ported here.
    static func isParallel(_ run: PiSubagentRunRecord) -> Bool {
        run.mode == .parallel && (run.children?.isEmpty == false)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let t = value?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }

    private static func statusColor(_ status: PiSubagentRunStatus) -> NSColor {
        switch status {
        case .queued, .starting, .running: return .systemBlue
        case .blocked: return .systemOrange
        case .completed: return .systemGreen
        case .failed: return .systemRed
        case .stopped, .disconnected: return .secondaryLabelColor
        }
    }

    private static func formattedDuration(_ milliseconds: Int) -> String {
        let seconds = max(0, milliseconds) / 1000
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m \(seconds % 60)s" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    private static func compactNumber(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return "\(value / 1_000)k" }
        return "\(value)"
    }
}

// MARK: - Activity glyph (avatar + rotating ring when active)

private final class PiAgentNativeSubagentGlyph: NSView {
    private let bgLayer = CAShapeLayer()
    private let strokeLayer = CAShapeLayer()
    private let ringLayer = CAShapeLayer()
    private let avatar = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(bgLayer)
        layer?.addSublayer(strokeLayer)
        layer?.addSublayer(ringLayer)
        strokeLayer.fillColor = NSColor.clear.cgColor
        strokeLayer.lineWidth = 1
        ringLayer.fillColor = NSColor.clear.cgColor
        ringLayer.lineWidth = 2
        ringLayer.lineCap = .round
        ringLayer.strokeStart = 0
        ringLayer.strokeEnd = 0.22
        avatar.translatesAutoresizingMaskIntoConstraints = false
        avatar.imageScaling = .scaleProportionallyUpOrDown
        avatar.wantsLayer = true
        avatar.layer?.cornerRadius = 14
        avatar.layer?.masksToBounds = true
        addSubview(avatar)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 34),
            heightAnchor.constraint(equalToConstant: 34),
            avatar.widthAnchor.constraint(equalToConstant: 28),
            avatar.heightAnchor.constraint(equalToConstant: 28),
            avatar.centerXAnchor.constraint(equalTo: centerXAnchor),
            avatar.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }

    func configure(color: NSColor, isActive: Bool, avatarURL: URL?) {
        bgLayer.fillColor = color.withAlphaComponent(isActive ? 0.10 : 0.06).cgColor
        strokeLayer.strokeColor = color.withAlphaComponent(isActive ? 0.22 : 0.12).cgColor
        ringLayer.strokeColor = color.cgColor
        ringLayer.isHidden = !isActive
        if let nsImage = AgentImageLoader.image(at: avatarURL) {
            avatar.image = nsImage
            avatar.contentTintColor = nil
        } else {
            avatar.image = NSImage(systemSymbolName: "paperplane", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 18, weight: .medium))
            avatar.contentTintColor = color
        }
        if isActive { startSpin() } else { ringLayer.removeAnimation(forKey: "spin") }
        needsLayout = true
    }

    private func startSpin() {
        guard ringLayer.animation(forKey: "spin") == nil else { return }
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = 2 * Double.pi
        spin.duration = 6
        spin.repeatCount = .infinity
        ringLayer.add(spin, forKey: "spin")
    }

    override func layout() {
        super.layout()
        let circle = CGPath(ellipseIn: bounds.insetBy(dx: 0.5, dy: 0.5), transform: nil)
        bgLayer.path = circle
        strokeLayer.path = circle
        bgLayer.frame = bounds; strokeLayer.frame = bounds
        ringLayer.frame = bounds
        ringLayer.path = CGPath(ellipseIn: bounds.insetBy(dx: 2, dy: 2), transform: nil)
        // Rotate around center.
        ringLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        ringLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
    }
}

// MARK: - Native subagent card view

final class PiAgentNativeSubagentRunCardView: NSView, PiAgentNativeRowContent {
    private let surface = NativeCardSurface()
    private let glyph = PiAgentNativeSubagentGlyph()
    private let nameLabel = NSTextField(labelWithString: "")
    private let runIDLabel = NSTextField(labelWithString: "")
    private let runIDCapsule = NativeCardSurface()
    private let statusLabel = NSTextField(labelWithString: "")
    private let taskHeader = NSTextField(labelWithString: "Task")
    private let taskCard = NativeCardSurface()
    private let markdownContainer = NativeMarkdownTextContainer()
    private let markdownApplier = MarkdownSourceApplier()
    private let metricsStack = NSStackView()
    private let buttonStack = NSStackView()

    private var payload: NativeSubagentCardPayload?

    var onIntrinsicHeightChange: (() -> Void)?

    private let pad: CGFloat = 14
    private let taskHPad: CGFloat = 12
    private let taskVPad: CGFloat = 10

    private var taskTopC: NSLayoutConstraint!
    private var metricsTopC: NSLayoutConstraint!

    required init() {
        super.init(frame: .zero)
        wantsLayer = true

        surface.translatesAutoresizingMaskIntoConstraints = false
        surface.cardCornerRadius = 14
        addSubview(surface)

        nameLabel.font = NSFont.preferredFont(forTextStyle: .headline)
        nameLabel.lineBreakMode = .byTruncatingTail

        runIDLabel.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
        runIDLabel.textColor = AppTheme.ns(AppTheme.mutedText)
        runIDCapsule.translatesAutoresizingMaskIntoConstraints = false
        runIDCapsule.cardCornerRadius = 6
        runIDCapsule.fillColor = AppTheme.ns(AppTheme.contentSubtleFill.opacity(0.65))
        runIDCapsule.strokeColor = AppTheme.ns(AppTheme.contentStroke)

        statusLabel.font = NativeTranscriptFont.caption(.semibold)

        let headerStack = NSStackView()
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        headerStack.orientation = .horizontal
        headerStack.spacing = 10
        headerStack.alignment = .centerY
        let titleStack = NSStackView()
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 3
        let nameRow = NSStackView(views: [nameLabel, runIDCapsule])
        nameRow.orientation = .horizontal
        nameRow.spacing = 7
        nameRow.alignment = .firstBaseline
        titleStack.addArrangedSubview(nameRow)
        titleStack.addArrangedSubview(statusLabel)
        headerStack.addArrangedSubview(glyph)
        headerStack.addArrangedSubview(titleStack)
        headerStack.addArrangedSubview(NSView())  // spacer
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 6
        headerStack.addArrangedSubview(buttonStack)

        runIDLabel.translatesAutoresizingMaskIntoConstraints = false
        runIDCapsule.addSubview(runIDLabel)
        NSLayoutConstraint.activate([
            runIDLabel.leadingAnchor.constraint(equalTo: runIDCapsule.leadingAnchor, constant: 5),
            runIDLabel.trailingAnchor.constraint(equalTo: runIDCapsule.trailingAnchor, constant: -5),
            runIDLabel.topAnchor.constraint(equalTo: runIDCapsule.topAnchor, constant: 2),
            runIDLabel.bottomAnchor.constraint(equalTo: runIDCapsule.bottomAnchor, constant: -2)
        ])

        taskHeader.font = NativeTranscriptFont.caption(.semibold)
        taskHeader.textColor = AppTheme.ns(AppTheme.mutedText)
        taskCard.translatesAutoresizingMaskIntoConstraints = false
        taskCard.cardCornerRadius = 14
        taskCard.fillColor = AppTheme.ns(AppTheme.contentSubtleFill.opacity(0.65))
        taskCard.strokeColor = AppTheme.ns(AppTheme.contentStroke)
        markdownContainer.translatesAutoresizingMaskIntoConstraints = false
        let taskInner = NSStackView(views: [taskHeader, markdownContainer])
        taskInner.translatesAutoresizingMaskIntoConstraints = false
        taskInner.orientation = .vertical
        taskInner.alignment = .leading
        taskInner.spacing = 8
        taskCard.addSubview(taskInner)
        NSLayoutConstraint.activate([
            taskInner.leadingAnchor.constraint(equalTo: taskCard.leadingAnchor, constant: taskHPad),
            taskInner.trailingAnchor.constraint(equalTo: taskCard.trailingAnchor, constant: -taskHPad),
            taskInner.topAnchor.constraint(equalTo: taskCard.topAnchor, constant: taskVPad),
            taskInner.bottomAnchor.constraint(equalTo: taskCard.bottomAnchor, constant: -taskVPad),
            markdownContainer.widthAnchor.constraint(equalTo: taskInner.widthAnchor)
        ])

        metricsStack.translatesAutoresizingMaskIntoConstraints = false
        metricsStack.orientation = .horizontal
        metricsStack.spacing = 10

        surface.addSubview(headerStack)
        surface.addSubview(taskCard)
        surface.addSubview(metricsStack)

        taskTopC = taskCard.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 12)
        metricsTopC = metricsStack.topAnchor.constraint(equalTo: taskCard.bottomAnchor, constant: 12)
        let metricsBottom = metricsStack.bottomAnchor.constraint(equalTo: surface.bottomAnchor, constant: -pad)
        metricsBottom.priority = NSLayoutConstraint.Priority(999)

        NSLayoutConstraint.activate([
            surface.topAnchor.constraint(equalTo: topAnchor),
            surface.bottomAnchor.constraint(equalTo: bottomAnchor),
            surface.leadingAnchor.constraint(equalTo: leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerStack.topAnchor.constraint(equalTo: surface.topAnchor, constant: pad),
            headerStack.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: pad),
            headerStack.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -pad),
            taskTopC,
            taskCard.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: pad),
            taskCard.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -pad),
            metricsTopC,
            metricsStack.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: pad),
            metricsStack.trailingAnchor.constraint(lessThanOrEqualTo: surface.trailingAnchor, constant: -pad),
            metricsBottom
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }

    func configure(payload: NativeSubagentCardPayload, width rowWidth: CGFloat) {
        self.payload = payload
        surface.fillColor = AppTheme.ns(AppTheme.contentFill.opacity(0.62))
        surface.strokeColor = AppTheme.ns(AppTheme.contentStroke)
        glyph.configure(color: payload.statusColor, isActive: payload.isActive, avatarURL: payload.avatarURL)
        nameLabel.stringValue = payload.agentName
        runIDLabel.stringValue = payload.shortRunID
        runIDLabel.toolTip = payload.fullRunID
        statusLabel.stringValue = payload.statusText
        statusLabel.textColor = payload.statusColor

        markdownApplier.apply(source: payload.task, to: markdownContainer)

        rebuildMetrics(payload.metrics)
        rebuildButtons(payload)
        needsLayout = true
    }

    private func rebuildMetrics(_ metrics: [NativeSubagentCardPayload.Metric]) {
        metricsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        metricsTopC.constant = metrics.isEmpty ? 0 : 12
        for m in metrics {
            let icon = NSImageView()
            icon.image = NSImage(systemSymbolName: m.icon, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: NativeTranscriptFont.caption2Size, weight: .semibold))
            icon.contentTintColor = AppTheme.ns(AppTheme.mutedText)
            let label = NSTextField(labelWithString: m.text)
            label.font = NativeTranscriptFont.caption()
            label.textColor = AppTheme.ns(AppTheme.mutedText)
            let item = NSStackView(views: [icon, label])
            item.orientation = .horizontal
            item.spacing = 3
            metricsStack.addArrangedSubview(item)
        }
    }

    private func rebuildButtons(_ payload: NativeSubagentCardPayload) {
        buttonStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let info = NSButton(image: NSImage(systemSymbolName: "info.circle", accessibilityDescription: "Run details")!, target: self, action: #selector(showDetails(_:)))
        info.isBordered = false
        info.contentTintColor = AppTheme.ns(AppTheme.mutedText)
        info.toolTip = "Run details"
        buttonStack.addArrangedSubview(info)
        if payload.showGraph {
            buttonStack.addArrangedSubview(smallButton("Graph", #selector(openGraph)))
        }
        let sysPrompt = smallButton("System Prompt", #selector(showSystemPrompt(_:)))
        sysPrompt.isEnabled = payload.canOpenSystemPrompt
        buttonStack.addArrangedSubview(sysPrompt)
        buttonStack.addArrangedSubview(smallButton("Transcript", #selector(openTranscript)))
        if payload.isActive {
            let stop = smallButton("Stop", #selector(stop))
            stop.contentTintColor = .systemRed
            buttonStack.addArrangedSubview(stop)
        }
    }

    private func smallButton(_ title: String, _ action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        b.controlSize = .small
        b.font = NativeTranscriptFont.caption(.semibold)
        return b
    }

    // MARK: Actions

    @objc private func stop() { payload?.onStop() }
    @objc private func openTranscript() { payload?.onTranscript() }
    @objc private func openGraph() { payload?.onGraph() }

    @objc private func showDetails(_ sender: NSButton) {
        guard let payload else { return }
        let vc = PiAgentNativeKeyValuePopover(title: "Run details", rows: payload.detailRows, revealAction: payload.canReveal ? payload.onReveal : nil)
        let pop = NSPopover(); pop.behavior = .transient; pop.contentViewController = vc
        pop.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxX)
    }

    @objc private func showSystemPrompt(_ sender: NSButton) {
        guard let payload else { return }
        let pop = NSPopover(); pop.behavior = .transient
        pop.contentViewController = PiAgentNativeTextPopoverController(title: "Final Runtime System Prompt", text: payload.systemPromptText())
        pop.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
    }

    // MARK: Measure

    func measuredHeight(forWidth rowWidth: CGFloat) -> CGFloat {
        let innerTaskWidth = max(1, rowWidth - pad * 2 - taskHPad * 2)
        let headerH = max(34, ceil(nameLabel.intrinsicContentSize.height) + ceil(statusLabel.intrinsicContentSize.height) + 3)
        let taskH = taskVPad + ceil(taskHeader.intrinsicContentSize.height) + 8 + markdownContainer.measureHeight(forWidth: innerTaskWidth) + taskVPad
        let metricsH = (payload?.metrics.isEmpty == false) ? 12 + 16 : 0
        return ceil(pad + headerH + 12 + taskH + CGFloat(metricsH) + pad)
    }

    func prepareForReuseIfNeeded() { markdownApplier.cancel() }
}

// MARK: - Native key/value popover (run details)

final class PiAgentNativeKeyValuePopover: NSViewController {
    private let titleText: String
    private let rows: [(String, String)]
    private let revealAction: (() -> Void)?

    init(title: String, rows: [(String, String)], revealAction: (() -> Void)?) {
        self.titleText = title; self.rows = rows; self.revealAction = revealAction
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        let title = NSTextField(labelWithString: titleText)
        title.font = NSFont.preferredFont(forTextStyle: .headline)
        stack.addArrangedSubview(title)

        for (k, v) in rows {
            let key = NSTextField(labelWithString: k)
            key.font = NativeTranscriptFont.caption(.semibold)
            key.textColor = AppTheme.ns(AppTheme.mutedText)
            key.setContentHuggingPriority(.required, for: .horizontal)
            let val = NSTextField(labelWithString: v)
            val.font = NativeTranscriptFont.caption()
            val.isSelectable = true
            val.lineBreakMode = .byTruncatingMiddle
            let row = NSStackView(views: [key, val])
            row.orientation = .horizontal
            row.spacing = 10
            stack.addArrangedSubview(row)
        }
        if let revealAction {
            let reveal = NSButton(title: "Reveal Run Folder", target: self, action: #selector(revealTapped))
            reveal.bezelStyle = .rounded
            reveal.controlSize = .small
            objc_setAssociatedObject(reveal, &Self.actionKey, revealAction, .OBJC_ASSOCIATION_RETAIN)
            stack.addArrangedSubview(reveal)
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.widthAnchor.constraint(equalToConstant: 430)
        ])
        view = container
    }

    private static var actionKey: UInt8 = 0
    @objc private func revealTapped() { revealAction?() }
}
