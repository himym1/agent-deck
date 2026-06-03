import AppKit

// Native (pure AppKit) tool-group row. Mirrors `PiAgentTranscriptThreadCard`'s
// `toolGroupView`: a reply-column container (no outer card chrome, hover copy in
// the gutter) stacking up to three subtle-filled sub-cards — web activity, tool
// chips, and a file-changes/diff summary. The display models are computed in the
// items pass (see `NativeToolGroupModel.make`) so this view is a dumb renderer.

// MARK: - Display models

struct NativeToolGroupModel {
    var web: Web?
    var chips: Chips?
    var diff: Diff?
    var copyText: String

    struct Web {
        var title: String
        var callCount: String
        var hasErrors: Bool
        var rows: [Row]
        var hiddenCount: Int
        struct Row {
            var id: UUID
            var icon: String
            var title: String
            var detail: String?
            var isError: Bool
            var links: [Link]
        }
        struct Link { var title: String; var domain: String }
    }

    struct Chips {
        var callCount: String
        var hasErrors: Bool
        var items: [Chip]
        struct Chip { var icon: String; var name: String; var count: Int; var isError: Bool }
    }

    struct Diff {
        var fileCount: Int
        var rows: [PiAgentThreadDiffSummaryView.Row]
    }
}

// MARK: - Factory (pure mapping, single-sourced with the SwiftUI views)

extension NativeToolGroupModel {
    @MainActor
    static func make(
        group: PiAgentThreadToolGroup,
        visibility: PiAgentTranscriptVisibilitySettings,
        projectPath: String?
    ) -> NativeToolGroupModel? {
        let webActivities = group.activities.filter(\.isWebActivity)
        let toolActivities = group.activities.filter { !$0.isWebActivity }

        var web: Web?
        if visibility.showWebActivity, !webActivities.isEmpty {
            let display = Array(webActivities.prefix(4))
            web = Web(
                title: webTitle(for: webActivities),
                callCount: callCountText(webActivities),
                hasErrors: webActivities.contains(where: \.isError),
                rows: display.map { activity in
                    Web.Row(
                        id: activity.id,
                        icon: webIcon(for: activity.name),
                        title: webRowTitle(for: activity.name),
                        detail: activity.compactDetail,
                        isError: activity.isError,
                        links: activity.webLinks.map { Web.Link(title: $0.title, domain: $0.domain) }
                    )
                },
                hiddenCount: max(0, webActivities.count - display.count)
            )
        }

        var chips: Chips?
        if visibility.showToolCalls, !toolActivities.isEmpty {
            chips = Chips(
                callCount: callCountText(toolActivities),
                hasErrors: toolActivities.contains(where: \.isError),
                items: toolActivities.map { activity in
                    Chips.Chip(
                        icon: toolIcon(for: activity.name),
                        name: toolDisplayName(for: activity.name, count: activity.count),
                        count: activity.count,
                        isError: activity.isError
                    )
                }
            )
        }

        var diff: Diff?
        if visibility.showDiffs {
            let rows = PiAgentThreadDiffSummaryView.diffRows(from: toolActivities)
            let fileCount = PiAgentThreadDiffSummaryView.changedPaths(from: toolActivities).count
            if !rows.isEmpty {
                diff = Diff(fileCount: fileCount, rows: Array(rows.prefix(4)))
            }
        }

        guard web != nil || chips != nil || diff != nil else { return nil }
        let copyText = group.entries.map(\.text).joined(separator: "\n\n")
        return NativeToolGroupModel(web: web, chips: chips, diff: diff, copyText: copyText)
    }

    private static func callCountText(_ activities: [PiAgentTranscriptActivity]) -> String {
        let count = activities.reduce(0) { $0 + $1.count }
        return count == 1 ? "1 call" : "\(count) calls"
    }

    private static func webTitle(for activities: [PiAgentTranscriptActivity]) -> String {
        let names = Set(activities.map { $0.name.lowercased() })
        if names.count == 1, let name = names.first {
            switch name {
            case "web_search": return "Web search"
            case "fetch_content": return "Fetch content"
            case "get_search_content": return "Read web content"
            case "web_fetch": return "URL fetch"
            default: break
            }
        }
        return "Web"
    }

    private static func webRowTitle(for name: String) -> String {
        switch name.lowercased() {
        case "web_search": return "Search"
        case "fetch_content": return "Fetched"
        case "get_search_content": return "Read content"
        case "web_fetch": return "Fetched"
        default: return name.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private static func webIcon(for name: String) -> String {
        switch name.lowercased() {
        case "web_search": return "magnifyingglass"
        case "fetch_content", "get_search_content", "web_fetch": return "doc.text.magnifyingglass"
        default: return "globe"
        }
    }

    private static func toolDisplayName(for name: String, count: Int) -> String {
        switch name.lowercased() {
        case "bash": return "Shell"
        case "read": return "File read"
        case "edit": return "Edit"
        case "write": return "Write"
        case "set_session_plan": return "Plan"
        case "update_session_plan": return "Plan update"
        case "subagent": return count == 1 ? "Deck agent" : "Deck agents"
        case "web_search": return "Web search"
        case "fetch_content", "get_search_content", "web_fetch": return "Web content"
        default:
            return name
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
                .split(separator: " ")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
        }
    }

    private static func toolIcon(for name: String) -> String {
        switch name.lowercased() {
        case "bash": return "terminal"
        case "read": return "doc.text.magnifyingglass"
        case "edit", "write": return "pencil.and.outline"
        case "set_session_plan", "update_session_plan": return "checklist"
        case "subagent": return "person.2.wave.2"
        case "web_search", "fetch_content", "get_search_content", "web_fetch": return "globe"
        default: return "wrench.and.screwdriver"
        }
    }
}

// MARK: - Tool-group view

final class PiAgentNativeToolGroupView: PiAgentNativeCardRowView {
    private let sections = NSStackView()
    private var sectionsWidthC: NSLayoutConstraint!
    private var model: NativeToolGroupModel?
    /// Web rows whose link list is expanded (by row id).
    private var expandedWebRows: Set<UUID> = []

    private static let inlineLinkLimit = 5
    private static let subtleFill = AppTheme.ns(AppTheme.contentSubtleFill).withAlphaComponent(0.65)
    private static let subtleStroke = AppTheme.ns(AppTheme.contentStroke)
    private static let muted = AppTheme.ns(AppTheme.mutedText)

    override func commonSetup() {
        sections.translatesAutoresizingMaskIntoConstraints = false
        sections.orientation = .vertical
        sections.alignment = .leading
        sections.spacing = 8
        cardContent.addSubview(sections)
        sectionsWidthC = sections.widthAnchor.constraint(equalToConstant: 100)
        NSLayoutConstraint.activate([
            sections.topAnchor.constraint(equalTo: cardContent.topAnchor),
            sections.leadingAnchor.constraint(equalTo: cardContent.leadingAnchor),
            sections.bottomAnchor.constraint(equalTo: cardContent.bottomAnchor),
            sectionsWidthC
        ])
    }

    func configure(model: NativeToolGroupModel, width rowWidth: CGFloat) {
        self.model = model
        // Transparent outer (sub-cards carry their own chrome); reply-column width.
        applyCard(
            fill: .clear, stroke: .clear, cornerRadius: 0,
            hPad: 0, vPad: 0, placement: .leftAtCap,
            copyText: model.copyText, width: rowWidth
        )
        sectionsWidthC.constant = innerCardWidth(forRowWidth: rowWidth)
        rebuildSections()
    }

    private func innerCardWidth(forRowWidth rowWidth: CGFloat) -> CGFloat {
        max(1, min(rowWidth, PiAgentBubbleWidth.replyCap(for: rowWidth)))
    }

    override func contentHeight(forInnerWidth innerWidth: CGFloat) -> CGFloat {
        sectionsWidthC.constant = innerWidth
        sections.layoutSubtreeIfNeeded()
        return ceil(sections.fittingSize.height)
    }

    private func rebuildSections() {
        sections.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard let model else { return }
        if let web = model.web { sections.addArrangedSubview(buildWebCard(web)) }
        if let chips = model.chips { sections.addArrangedSubview(buildChipsCard(chips)) }
        if let diff = model.diff { sections.addArrangedSubview(buildDiffCard(diff)) }
        for view in sections.arrangedSubviews {
            view.widthAnchor.constraint(equalTo: sections.widthAnchor).isActive = true
        }
    }

    // MARK: Sub-card chrome

    private func makeSubCard(cornerRadius: CGFloat = 12, fill: NSColor = subtleFill, stroke: NSColor = subtleStroke) -> NativeCardSurface {
        let card = NativeCardSurface()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.cardCornerRadius = cornerRadius
        card.fillColor = fill
        card.strokeColor = stroke
        return card
    }

    private static func captionBold() -> NSFont {
        NSFontManager.shared.convert(NSFont.preferredFont(forTextStyle: .caption1), toHaveTrait: .boldFontMask)
    }

    private static func label(_ text: String, font: NSFont, color: NSColor = .labelColor, wraps: Bool = false) -> NSTextField {
        let f = wraps ? NSTextField(wrappingLabelWithString: text) : NSTextField(labelWithString: text)
        f.translatesAutoresizingMaskIntoConstraints = false
        f.font = font
        f.textColor = color
        f.lineBreakMode = wraps ? .byWordWrapping : .byTruncatingTail
        return f
    }

    // MARK: Web card

    private func buildWebCard(_ web: NativeToolGroupModel.Web) -> NSView {
        let card = makeSubCard()
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8

        // Header
        let header = NSStackView()
        header.orientation = .horizontal
        header.spacing = 8
        let globe = NSImageView()
        globe.image = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
        globe.contentTintColor = web.hasErrors ? AppTheme.ns(AppTheme.roleError) : Self.muted
        header.addArrangedSubview(globe)
        header.addArrangedSubview(Self.label(web.title, font: Self.captionBold()))
        header.addArrangedSubview(Self.label(web.callCount, font: NSFont.preferredFont(forTextStyle: .caption1), color: Self.muted))
        stack.addArrangedSubview(header)

        for row in web.rows {
            stack.addArrangedSubview(buildWebRow(row, cardWidth: card))
        }
        if web.hiddenCount > 0 {
            let suffix = web.hiddenCount == 1 ? "" : "s"
            stack.addArrangedSubview(Self.label("\(web.hiddenCount) older web update\(suffix) hidden",
                                                font: NSFont.preferredFont(forTextStyle: .caption2), color: Self.muted))
        }

        embed(stack, in: card, hInset: 10, vInset: 8)
        return card
    }

    private func buildWebRow(_ row: NativeToolGroupModel.Web.Row, cardWidth: NSView) -> NSView {
        let rowStack = NSStackView()
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        rowStack.orientation = .vertical
        rowStack.alignment = .leading
        rowStack.spacing = 5

        let titleRow = NSStackView()
        titleRow.orientation = .horizontal
        titleRow.spacing = 7
        titleRow.alignment = .firstBaseline
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: row.icon, accessibilityDescription: nil)
        icon.contentTintColor = row.isError ? AppTheme.ns(AppTheme.roleError) : Self.muted
        titleRow.addArrangedSubview(icon)
        titleRow.addArrangedSubview(Self.label(row.title, font: Self.captionBold()))
        if let detail = row.detail {
            titleRow.addArrangedSubview(Self.label(detail, font: NSFont.preferredFont(forTextStyle: .caption1), color: Self.muted))
        }
        rowStack.addArrangedSubview(titleRow)

        if !row.links.isEmpty {
            let expanded = expandedWebRows.contains(row.id)
            let shown = expanded ? row.links : Array(row.links.prefix(Self.inlineLinkLimit))
            let linksStack = NSStackView()
            linksStack.orientation = .vertical
            linksStack.alignment = .leading
            linksStack.spacing = 3
            linksStack.edgeInsets = NSEdgeInsets(top: 0, left: 21, bottom: 0, right: 0)
            for link in shown {
                let linkRow = NSStackView()
                linkRow.orientation = .horizontal
                linkRow.spacing = 6
                linkRow.alignment = .firstBaseline
                linkRow.addArrangedSubview(Self.label("•", font: NSFont.preferredFont(forTextStyle: .caption2), color: Self.muted))
                linkRow.addArrangedSubview(Self.label(link.title, font: NSFontManager.shared.convert(NSFont.preferredFont(forTextStyle: .caption2), toHaveTrait: .boldFontMask)))
                linkRow.addArrangedSubview(Self.label(link.domain, font: NSFont.preferredFont(forTextStyle: .caption2), color: Self.muted))
                linksStack.addArrangedSubview(linkRow)
            }
            if row.links.count > Self.inlineLinkLimit {
                let more = NSButton(title: expanded ? "Show fewer results" : "+\(row.links.count - Self.inlineLinkLimit) more results",
                                    target: self, action: #selector(toggleWebRow(_:)))
                more.isBordered = false
                more.bezelStyle = .inline
                more.font = NSFontManager.shared.convert(NSFont.preferredFont(forTextStyle: .caption2), toHaveTrait: .boldFontMask)
                more.contentTintColor = AppTheme.ns(AppTheme.brandAccent)
                more.identifier = NSUserInterfaceItemIdentifier(row.id.uuidString)
                linksStack.addArrangedSubview(more)
            }
            rowStack.addArrangedSubview(linksStack)
        }
        return rowStack
    }

    @objc private func toggleWebRow(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let id = UUID(uuidString: raw) else { return }
        if expandedWebRows.contains(id) { expandedWebRows.remove(id) } else { expandedWebRows.insert(id) }
        rebuildSections()
        notifyContentHeightChanged()
    }

    // MARK: Chips card

    private func buildChipsCard(_ chips: NativeToolGroupModel.Chips) -> NSView {
        let card = makeSubCard()
        let row = NSStackView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.spacing = 10
        row.alignment = .centerY

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: chips.hasErrors ? "exclamationmark.triangle" : "wrench.and.screwdriver", accessibilityDescription: nil)
        icon.contentTintColor = chips.hasErrors ? AppTheme.ns(AppTheme.roleError) : Self.muted
        row.addArrangedSubview(icon)
        row.addArrangedSubview(Self.label("Tools", font: Self.captionBold()))
        row.addArrangedSubview(Self.label(chips.callCount, font: NSFont.preferredFont(forTextStyle: .caption1), color: Self.muted))

        let chipRow = NSStackView()
        chipRow.orientation = .horizontal
        chipRow.spacing = 6
        for chip in chips.items { chipRow.addArrangedSubview(buildChip(chip)) }
        // Horizontal scroll for overflow, matching the SwiftUI ScrollView.
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.documentView = chipRow
        chipRow.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            chipRow.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            chipRow.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            chipRow.bottomAnchor.constraint(equalTo: scroll.contentView.bottomAnchor),
            scroll.heightAnchor.constraint(equalTo: chipRow.heightAnchor)
        ])
        row.addArrangedSubview(scroll)

        embed(row, in: card, hInset: 10, vInset: 7)
        return card
    }

    private func buildChip(_ chip: NativeToolGroupModel.Chips.Chip) -> NSView {
        let color = chip.isError ? AppTheme.ns(AppTheme.roleError) : Self.muted
        let capsule = NSView()
        capsule.translatesAutoresizingMaskIntoConstraints = false
        capsule.wantsLayer = true
        capsule.layer?.cornerRadius = 9
        capsule.layer?.backgroundColor = (chip.isError ? AppTheme.ns(AppTheme.roleError) : Self.subtleStroke)
            .withAlphaComponent(AppTheme.roleChipOpacity).cgColor

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.spacing = 5
        stack.alignment = .centerY
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: chip.icon, accessibilityDescription: nil)
        icon.contentTintColor = color
        stack.addArrangedSubview(icon)
        stack.addArrangedSubview(Self.label(chip.name, font: NSFont.preferredFont(forTextStyle: .caption1), color: color))
        let count = Self.label("\(chip.count)", font: NSFontManager.shared.convert(NSFont.monospacedDigitSystemFont(ofSize: NSFont.preferredFont(forTextStyle: .caption2).pointSize, weight: .bold), toHaveTrait: []), color: color)
        stack.addArrangedSubview(count)
        embed(stack, in: capsule, hInset: 7, vInset: 3)
        return capsule
    }

    // MARK: Diff card

    private func buildDiffCard(_ diff: NativeToolGroupModel.Diff) -> NSView {
        let card = makeSubCard()
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 7

        let header = NSStackView()
        header.orientation = .horizontal
        header.spacing = 8
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "doc.text.magnifyingglass", accessibilityDescription: nil)
        icon.contentTintColor = Self.muted
        header.addArrangedSubview(icon)
        header.addArrangedSubview(Self.label("Changes", font: Self.captionBold()))
        header.addArrangedSubview(Self.label(diff.fileCount == 1 ? "1 file" : "\(diff.fileCount) files",
                                             font: NSFont.preferredFont(forTextStyle: .caption1), color: Self.muted))
        stack.addArrangedSubview(header)

        for row in diff.rows { stack.addArrangedSubview(buildDiffRow(row)) }
        let hidden = diff.rows.count > 4 ? diff.rows.count - 4 : 0
        if hidden > 0 {
            stack.addArrangedSubview(Self.label("\(hidden) more changed file\(hidden == 1 ? "" : "s") hidden",
                                                font: NSFont.preferredFont(forTextStyle: .caption2), color: Self.muted))
        }

        embed(stack, in: card, hInset: 10, vInset: 8)
        return card
    }

    private func buildDiffRow(_ row: PiAgentThreadDiffSummaryView.Row) -> NSView {
        let inner = makeSubCard(cornerRadius: 10, fill: AppTheme.ns(AppTheme.textContentFill).withAlphaComponent(0.75), stroke: .clear)
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6

        let head = NSStackView()
        head.orientation = .horizontal
        head.spacing = 8
        head.alignment = .firstBaseline
        head.addArrangedSubview(Self.label(row.path.truncatedMiddle(max: 54), font: Self.captionBold()))
        head.addArrangedSubview(Self.label(row.changeCountText, font: NSFontManager.shared.convert(NSFont.monospacedDigitSystemFont(ofSize: NSFont.preferredFont(forTextStyle: .caption2).pointSize, weight: .semibold), toHaveTrait: []), color: Self.muted))
        let openBtn = NSButton(title: "Open", target: self, action: #selector(openDiff(_:)))
        openBtn.bezelStyle = .rounded
        openBtn.controlSize = .small
        openBtn.font = NSFont.preferredFont(forTextStyle: .caption2)
        openBtn.identifier = NSUserInterfaceItemIdentifier("diff:\(row.path)")
        diffByPath[row.path] = (title: row.path, text: row.diff)
        head.addArrangedSubview(openBtn)
        stack.addArrangedSubview(head)

        // Compact colored preview (capped lines), matching PiAgentCompactDiffPreview.
        stack.addArrangedSubview(buildDiffPreview(row.diff))

        embed(stack, in: inner, hInset: 8, vInset: 8)
        return inner
    }

    private var diffByPath: [String: (title: String, text: String)] = [:]

    private func buildDiffPreview(_ diff: String) -> NSView {
        let textView = NSTextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true

        let font = NSFont.monospacedSystemFont(ofSize: NSFont.preferredFont(forTextStyle: .caption2).pointSize, weight: .regular)
        let attr = NSMutableAttributedString()
        let lines = diff.split(separator: "\n", omittingEmptySubsequences: false).prefix(12)
        let added = NSColor.systemGreen
        let removed = NSColor.systemRed
        for (i, line) in lines.enumerated() {
            let s = String(line)
            let color: NSColor
            if s.hasPrefix("+") && !s.hasPrefix("+++") { color = added }
            else if s.hasPrefix("-") && !s.hasPrefix("---") { color = removed }
            else { color = Self.muted }
            attr.append(NSAttributedString(string: s + (i < lines.count - 1 ? "\n" : ""), attributes: [.font: font, .foregroundColor: color]))
        }
        textView.textStorage?.setAttributedString(attr)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textView
    }

    @objc private func openDiff(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, raw.hasPrefix("diff:") else { return }
        let path = String(raw.dropFirst("diff:".count))
        guard let entry = diffByPath[path] else { return }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = PiAgentNativeTextPopoverController(title: entry.title, text: entry.text)
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
    }

    // MARK: Helpers

    private func embed(_ view: NSView, in container: NSView, hInset: CGFloat, vInset: CGFloat) {
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: hInset),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -hInset),
            view.topAnchor.constraint(equalTo: container.topAnchor, constant: vInset),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -vInset)
        ])
    }

    override func prepareForReuseIfNeeded() {
        super.prepareForReuseIfNeeded()
        expandedWebRows.removeAll()
        diffByPath.removeAll()
    }
}
