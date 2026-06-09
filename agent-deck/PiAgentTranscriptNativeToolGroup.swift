import AppKit
import SwiftUI

// Native (pure AppKit) tool-group row. Mirrors `PiAgentTranscriptThreadCard`'s
// `toolGroupView`: a reply-column container (no outer card chrome, hover copy in
// the gutter) stacking up to two subtle-filled sub-cards — web activity and a
// file-changes/diff summary. (Per-tool call counts are not shown inline; they are
// recapped in the Session resources popover via `toolCallRecap`.) The display
// models are computed in the items pass (see `NativeToolGroupModel.make`) so this
// view is a dumb renderer.

// MARK: - Display models

struct NativeToolGroupModel {
    var web: Web?
    var diff: Diff?

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
        struct Link { var title: String; var url: String; var domain: String }
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
                        links: activity.webLinks.map { Web.Link(title: $0.title, url: $0.url, domain: $0.domain) }
                    )
                },
                hiddenCount: max(0, webActivities.count - display.count)
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

        guard web != nil || diff != nil else { return nil }
        return NativeToolGroupModel(web: web, diff: diff)
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

    private static func toolVerb(for name: String) -> String {
        switch name.lowercased() {
        case "bash": return "Shell"
        case "read": return "Read"
        case "edit": return "Edit"
        case "write": return "Write"
        case "set_session_plan", "update_session_plan": return "Plan"
        case "subagent": return "Agent"
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

    /// Session-wide per-tool recap (non-web tool calls only), surfaced in the
    /// Session resources popover rather than inline in the transcript. Groups every
    /// tool/error entry by display verb, summing successes and errors across the
    /// whole conversation. Tool errors carry a `Tool: ` title prefix, so model
    /// errors (and other `.error` rows) are excluded.
    @MainActor
    static func toolCallRecap(from entries: [PiAgentTranscriptEntry]) -> [PiAgentToolCallRecapItem] {
        let relevant = entries.filter { $0.role == .tool || ($0.role == .error && $0.title.hasPrefix("Tool: ")) }
        var order: [String] = []
        var byVerb: [String: PiAgentToolCallRecapItem] = [:]
        for activity in PiAgentTranscriptActivity.make(from: relevant) where !activity.isWebActivity {
            let verb = toolVerb(for: activity.name)
            let errors = activity.entries.filter { $0.role == .error }.count
            let success = max(0, activity.count - errors)
            if var existing = byVerb[verb] {
                existing.successCount += success
                existing.errorCount += errors
                byVerb[verb] = existing
            } else {
                order.append(verb)
                byVerb[verb] = PiAgentToolCallRecapItem(
                    icon: toolIcon(for: activity.name),
                    name: verb,
                    successCount: success,
                    errorCount: errors
                )
            }
        }
        return order.compactMap { byVerb[$0] }
    }
}

/// One row in the Session resources "Tool calls" recap: a tool's display verb,
/// its icon, and aggregate success/error counts across the session.
struct PiAgentToolCallRecapItem: Identifiable {
    var id: String { name }
    var icon: String
    var name: String
    var successCount: Int
    var errorCount: Int
}

// MARK: - Tool-group view

final class PiAgentNativeToolGroupView: PiAgentNativeCardRowView {
    private let sections = NSStackView()
    private var sectionsWidthC: NSLayoutConstraint!
    private var model: NativeToolGroupModel?
    /// Web rows whose link list is expanded (by row id).
    private var expandedWebRows: Set<UUID> = []
    /// Diff rows whose preview is expanded past 10 lines (by path).
    private var expandedDiffRows: Set<String> = []

    private static let inlineLinkLimit = 5
    // Quiet hairline transcript-card surface — see `AppTheme.Chat.cardFill`.
    // Computed (not `static let`) so each sub-card build re-resolves against the
    // active theme rather than snapshotting the launch theme.
    private static var subtleFill: NSColor { AppTheme.ns(AppTheme.Chat.cardFill) }
    private static var subtleStroke: NSColor { AppTheme.ns(AppTheme.Chat.cardStroke) }
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
            copyText: nil, width: rowWidth
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
        diffByPath.removeAll()
        guard let model else { return }
        if let web = model.web { sections.addArrangedSubview(buildWebCard(web)) }
        if let diff = model.diff { sections.addArrangedSubview(buildDiffCard(diff)) }
        for view in sections.arrangedSubviews {
            view.widthAnchor.constraint(equalTo: sections.widthAnchor).isActive = true
        }
    }

    // MARK: Sub-card chrome

    private func makeSubCard(cornerRadius: CGFloat = AppTheme.Chat.cardCornerRadius, fill: NSColor = subtleFill, stroke: NSColor = subtleStroke) -> NativeCardSurface {
        let card = NativeCardSurface()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.cardCornerRadius = cornerRadius
        card.fillColor = fill
        card.strokeColor = stroke
        return card
    }

    private static func captionBold() -> NSFont { NativeTranscriptFont.caption(.semibold) }

    /// A sub-card header glyph on the shared transcript header scale (16pt box,
    /// `headerIcon`), so "Web"/"Changes" titles read at the same size as the
    /// memory / status / bubble cards rather than a smaller competing scale.
    private static func headerGlyph(_ name: String, tint: NSColor) -> NSImageView {
        let view = NSImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.image = NativeTranscriptFont.headerIcon(name)
        view.contentTintColor = tint
        view.imageScaling = .scaleProportionallyDown
        view.setContentHuggingPriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: NativeTranscriptFont.headerIconSize),
            view.heightAnchor.constraint(equalToConstant: NativeTranscriptFont.headerIconSize)
        ])
        return view
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
        stack.spacing = 10

        // Header: globe + title on the left, call count pinned to the right edge.
        let header = NSStackView()
        header.orientation = .horizontal
        header.spacing = 8
        header.alignment = .centerY
        let globe = Self.headerGlyph("globe", tint: web.hasErrors ? AppTheme.ns(AppTheme.roleError) : Self.muted)
        header.addArrangedSubview(globe)
        header.addArrangedSubview(Self.label(web.title, font: NativeTranscriptFont.header))
        header.addArrangedSubview(NSView())   // flexible spacer pushes the count right
        header.addArrangedSubview(Self.label(web.callCount, font: NativeTranscriptFont.caption(), color: Self.muted))
        stack.addArrangedSubview(header)
        header.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        for row in web.rows {
            let rowView = buildWebRow(row)
            stack.addArrangedSubview(rowView)
            rowView.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        if web.hiddenCount > 0 {
            let suffix = web.hiddenCount == 1 ? "" : "s"
            stack.addArrangedSubview(Self.label("\(web.hiddenCount) older web update\(suffix) hidden",
                                                font: NativeTranscriptFont.caption(), color: Self.muted))
        }

        embed(stack, in: card, hInset: AppTheme.Chat.cardHPadding, vInset: AppTheme.Chat.cardVPadding)
        return card
    }

    /// 14pt icon column + 7pt gap, so the indented source rows (which carry the
    /// same 21pt leading inset) line up under the query title.
    private static let webRowIndent: CGFloat = 21

    private func buildWebRow(_ row: NativeToolGroupModel.Web.Row) -> NSView {
        let rowStack = NSStackView()
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        rowStack.orientation = .vertical
        rowStack.alignment = .leading
        rowStack.spacing = 6

        let hasLinks = !row.links.isEmpty

        // Primary line: icon + headline. For searches the query itself is the
        // headline (the source rows give it context); other calls show the verb
        // (bold) followed by their detail (muted), separated by weight not a glyph.
        let titleRow = NSStackView()
        titleRow.orientation = .horizontal
        titleRow.spacing = 7
        titleRow.alignment = .centerY
        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.image = NSImage(systemSymbolName: row.icon, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: NativeTranscriptFont.caption2Size, weight: .semibold))
        icon.contentTintColor = row.isError ? AppTheme.ns(AppTheme.roleError) : Self.muted
        icon.imageScaling = .scaleProportionallyDown
        icon.widthAnchor.constraint(equalToConstant: 14).isActive = true
        titleRow.addArrangedSubview(icon)
        if hasLinks {
            let query = (row.detail?.isEmpty == false) ? row.detail! : row.title
            let p = Self.label(query, font: Self.captionBold())
            p.lineBreakMode = .byTruncatingTail
            titleRow.addArrangedSubview(p)
        } else {
            titleRow.addArrangedSubview(Self.label(row.title, font: Self.captionBold()))
            if let detail = row.detail, !detail.isEmpty {
                let d = Self.label(detail, font: NativeTranscriptFont.caption(), color: Self.muted)
                d.lineBreakMode = .byTruncatingMiddle
                titleRow.addArrangedSubview(d)
            }
        }
        rowStack.addArrangedSubview(titleRow)
        titleRow.widthAnchor.constraint(equalTo: rowStack.widthAnchor).isActive = true

        // Source rows: tappable, open the URL, indented under the query.
        if hasLinks {
            let expanded = expandedWebRows.contains(row.id)
            let shown = expanded ? row.links : Array(row.links.prefix(Self.inlineLinkLimit))
            let sources = NSStackView()
            sources.translatesAutoresizingMaskIntoConstraints = false
            sources.orientation = .vertical
            sources.alignment = .leading
            sources.spacing = 1
            for link in shown {
                let sourceRow = PiAgentNativeWebSourceRow(leadingInset: Self.webRowIndent)
                sourceRow.configure(title: link.title, domain: link.domain, url: link.url)
                sources.addArrangedSubview(sourceRow)
                sourceRow.widthAnchor.constraint(equalTo: sources.widthAnchor).isActive = true
            }
            if row.links.count > Self.inlineLinkLimit {
                let more = NSButton(title: expanded ? "Show fewer results" : "+\(row.links.count - Self.inlineLinkLimit) more results",
                                    target: self, action: #selector(toggleWebRow(_:)))
                more.isBordered = false
                more.bezelStyle = .inline
                more.font = NativeTranscriptFont.caption(.semibold)
                more.contentTintColor = AppTheme.ns(AppTheme.brandAccent)
                more.identifier = NSUserInterfaceItemIdentifier(row.id.uuidString)
                let wrap = NSStackView(views: [more])
                wrap.edgeInsets = NSEdgeInsets(top: 2, left: Self.webRowIndent, bottom: 0, right: 0)
                sources.addArrangedSubview(wrap)
            }
            rowStack.addArrangedSubview(sources)
            sources.widthAnchor.constraint(equalTo: rowStack.widthAnchor).isActive = true
        }
        return rowStack
    }

    @objc private func toggleWebRow(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let id = UUID(uuidString: raw) else { return }
        if expandedWebRows.contains(id) { expandedWebRows.remove(id) } else { expandedWebRows.insert(id) }
        rebuildSections()
        notifyContentHeightChanged()
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
        header.alignment = .centerY
        header.addArrangedSubview(Self.headerGlyph("plusminus", tint: Self.muted))
        header.addArrangedSubview(Self.label("Changes", font: NativeTranscriptFont.header))
        header.addArrangedSubview(NSView())   // flexible spacer pushes the count right
        header.addArrangedSubview(Self.label(diff.fileCount == 1 ? "1 file" : "\(diff.fileCount) files",
                                             font: NativeTranscriptFont.caption(), color: Self.muted))
        stack.addArrangedSubview(header)
        header.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        for row in diff.rows { stack.addArrangedSubview(buildDiffRow(row)) }
        let hidden = diff.rows.count > 4 ? diff.rows.count - 4 : 0
        if hidden > 0 {
            stack.addArrangedSubview(Self.label("\(hidden) more changed file\(hidden == 1 ? "" : "s") hidden",
                                                font: NativeTranscriptFont.caption(), color: Self.muted))
        }

        embed(stack, in: card, hInset: AppTheme.Chat.cardHPadding, vInset: AppTheme.Chat.cardVPadding)
        return card
    }

    private func buildDiffRow(_ row: PiAgentThreadDiffSummaryView.Row) -> NSView {
        let inner = makeSubCard(cornerRadius: AppTheme.Chat.subCardCornerRadius, fill: AppTheme.ns(AppTheme.textContentFill.opacity(0.75)), stroke: .clear)
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6

        let head = NSStackView()
        head.orientation = .horizontal
        head.spacing = 8
        head.alignment = .firstBaseline
        let pathLabel = Self.label(row.path.truncatedMiddle(max: 54), font: Self.captionBold())
        pathLabel.lineBreakMode = .byTruncatingMiddle
        head.addArrangedSubview(pathLabel)
        head.addArrangedSubview(Self.label(row.changeCountText,
                                           font: .monospacedDigitSystemFont(ofSize: NativeTranscriptFont.captionSize, weight: .semibold),
                                           color: Self.muted))
        head.addArrangedSubview(NSView())  // spacer
        let openBtn = NSButton(title: "Open", target: self, action: #selector(openDiff(_:)))
        openBtn.bezelStyle = .rounded
        openBtn.controlSize = .small
        openBtn.font = NativeTranscriptFont.caption2(.semibold)
        openBtn.identifier = NSUserInterfaceItemIdentifier(row.path)
        let copyBtn = NSButton(title: "Copy", target: self, action: #selector(copyDiff(_:)))
        copyBtn.bezelStyle = .rounded
        copyBtn.controlSize = .small
        copyBtn.font = NativeTranscriptFont.caption2(.semibold)
        copyBtn.identifier = NSUserInterfaceItemIdentifier(row.path)
        diffByPath[row.path] = row
        head.addArrangedSubview(openBtn)
        head.addArrangedSubview(copyBtn)
        stack.addArrangedSubview(head)
        head.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        stack.addArrangedSubview(buildDiffPreview(for: row))

        embed(stack, in: inner, hInset: 8, vInset: 8)
        return inner
    }

    private var diffByPath: [String: PiAgentThreadDiffSummaryView.Row] = [:]

    /// Compact colored diff preview — faithful to `PiAgentCompactDiffPreview`:
    /// filtered "meaningful" lines, a right-aligned gutter (prefix + line number)
    /// and content column with per-line tint, capped at 10 lines with an inline
    /// "Show N more lines" expander.
    private func buildDiffPreview(for row: PiAgentThreadDiffSummaryView.Row) -> NSView {
        let container = NSStackView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 0

        let lines = Self.meaningfulDiffLines(row.diff)
        let expanded = expandedDiffRows.contains(row.path)
        let visible = expanded ? lines : Array(lines.prefix(10))

        let linesStack = NSStackView()
        linesStack.translatesAutoresizingMaskIntoConstraints = false
        linesStack.orientation = .vertical
        linesStack.alignment = .leading
        linesStack.spacing = 0
        linesStack.wantsLayer = true
        linesStack.layer?.cornerRadius = AppTheme.Chat.codeCornerRadius
        linesStack.layer?.masksToBounds = true
        for line in visible { linesStack.addArrangedSubview(buildDiffLineRow(line)) }
        container.addArrangedSubview(linesStack)
        linesStack.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true
        for lineRow in linesStack.arrangedSubviews {
            lineRow.widthAnchor.constraint(equalTo: linesStack.widthAnchor).isActive = true
        }

        if lines.count > 10 {
            let title = expanded ? "Show fewer lines" : "Show \(lines.count - 10) more lines"
            let symbol = expanded ? "chevron.up" : "chevron.down"
            let more = NSButton(title: " " + title, target: self, action: #selector(toggleDiffRow(_:)))
            more.isBordered = false
            more.bezelStyle = .inline
            more.font = NativeTranscriptFont.caption()
            more.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            more.imagePosition = .imageLeading
            more.contentTintColor = Self.muted
            more.identifier = NSUserInterfaceItemIdentifier(row.path)
            let wrap = NSStackView(views: [more])
            wrap.edgeInsets = NSEdgeInsets(top: 3, left: 0, bottom: 0, right: 0)
            container.addArrangedSubview(wrap)
        }
        return container
    }

    private func buildDiffLineRow(_ line: DiffLine) -> NSView {
        let bg = NSView()
        bg.translatesAutoresizingMaskIntoConstraints = false
        bg.wantsLayer = true
        bg.layer?.backgroundColor = line.background.cgColor

        let mono = NSFont.monospacedSystemFont(ofSize: NativeTranscriptFont.captionSize, weight: .regular)
        let monoBold = NSFont.monospacedSystemFont(ofSize: NativeTranscriptFont.captionSize, weight: .semibold)

        let gutter = Self.label(line.gutter, font: monoBold, color: line.color)
        gutter.alignment = .right
        gutter.translatesAutoresizingMaskIntoConstraints = false

        let content = Self.label(line.content.isEmpty ? " " : line.content, font: mono, color: line.color)
        content.lineBreakMode = .byTruncatingTail
        content.translatesAutoresizingMaskIntoConstraints = false

        bg.addSubview(gutter)
        bg.addSubview(content)
        NSLayoutConstraint.activate([
            gutter.leadingAnchor.constraint(equalTo: bg.leadingAnchor),
            gutter.widthAnchor.constraint(equalToConstant: 40),
            gutter.topAnchor.constraint(equalTo: bg.topAnchor, constant: 1),
            gutter.bottomAnchor.constraint(equalTo: bg.bottomAnchor, constant: -1),
            content.leadingAnchor.constraint(equalTo: gutter.trailingAnchor, constant: 9),
            content.trailingAnchor.constraint(lessThanOrEqualTo: bg.trailingAnchor),
            content.centerYAnchor.constraint(equalTo: gutter.centerYAnchor)
        ])
        return bg
    }

    struct DiffLine {
        var gutter: String
        var content: String
        var color: NSColor
        var background: NSColor
    }

    private static func meaningfulDiffLines(_ diff: String) -> [DiffLine] {
        let added = AppTheme.ns(AppTheme.diffAdded)
        let removed = AppTheme.ns(AppTheme.diffRemoved)
        let addedBg = AppTheme.ns(AppTheme.diffAdded.opacity(AppTheme.roleFillStrongOpacity))
        let removedBg = AppTheme.ns(AppTheme.diffRemoved.opacity(AppTheme.roleFillStrongOpacity))
        return diff.split(separator: "\n", omittingEmptySubsequences: false).map(String.init).filter { line in
            guard !line.hasPrefix("diff --git"), !line.hasPrefix("index "), !line.hasPrefix("---"), !line.hasPrefix("+++") else { return false }
            return line.hasPrefix("+") || line.hasPrefix("-") || line.hasPrefix("@@")
        }.map { raw in
            if raw.hasPrefix("@@") {
                return DiffLine(gutter: "…", content: raw, color: Self.muted, background: .clear)
            }
            guard let first = raw.first, first == "+" || first == "-" || first == " " else {
                return DiffLine(gutter: " ", content: raw.trimmingCharacters(in: .whitespaces), color: Self.muted, background: .clear)
            }
            let prefix = String(first)
            let trimmedLeading = raw.dropFirst().drop(while: { $0 == " " })
            let numberPart = trimmedLeading.prefix(while: { $0.isNumber })
            let content = String(trimmedLeading.dropFirst(numberPart.count).drop(while: { $0 == " " }))
            let gutter = numberPart.isEmpty ? prefix : "\(prefix) \(numberPart)"
            let color: NSColor = first == "+" ? added : (first == "-" ? removed : Self.muted)
            let bg: NSColor = first == "+" ? addedBg : (first == "-" ? removedBg : .clear)
            return DiffLine(gutter: gutter, content: content, color: color, background: bg)
        }
    }

    @objc private func toggleDiffRow(_ sender: NSButton) {
        guard let path = sender.identifier?.rawValue else { return }
        if expandedDiffRows.contains(path) { expandedDiffRows.remove(path) } else { expandedDiffRows.insert(path) }
        rebuildSections()
        notifyContentHeightChanged()
    }

    @objc private func copyDiff(_ sender: NSButton) {
        guard let path = sender.identifier?.rawValue, let row = diffByPath[path] else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(row.diff, forType: .string)
        // Text-only button: confirm by swapping the title briefly.
        sender.title = "Copied"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { sender.title = "Copy" }
    }

    /// Present the full diff in a modal sheet (hosting the SwiftUI diff view — a
    /// modal is not a scroll hot path, so it's pixel-identical to the original).
    @objc private func openDiff(_ sender: NSButton) {
        guard let path = sender.identifier?.rawValue, let row = diffByPath[path],
              let host = window?.contentViewController else { return }
        var hosting: NSViewController?
        let sheet = PiAgentNativeFullDiffSheet(row: row) { [weak host] in
            if let hosting { host?.dismiss(hosting) }
        }
        let controller = NSHostingController(rootView: sheet)
        hosting = controller
        host.presentAsSheet(controller)
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
        expandedDiffRows.removeAll()
        diffByPath.removeAll()
    }
}

// MARK: - Web source row

/// One tappable web source: the page title, its domain (muted), and a trailing
/// chevron. Highlights on hover; opens the URL on click. Carries its own leading
/// inset so it aligns under the query title without a bullet marker.
private final class PiAgentNativeWebSourceRow: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let domainLabel = NSTextField(labelWithString: "")
    private let chevron = NSImageView()
    private var url: String = ""
    private var trackingArea: NSTrackingArea?

    private let vPad: CGFloat = 3
    private static let muted = AppTheme.ns(AppTheme.mutedText)
    private static let accent = AppTheme.ns(AppTheme.brandAccent)
    // Shared row-hover highlight from the design system (selection fill).
    private static let hoverFill = AppTheme.ns(AppTheme.selectionFill)

    init(leadingInset: CGFloat) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = AppTheme.Chat.chipCornerRadius
        layer?.cornerCurve = .continuous
        layer?.actions = ["backgroundColor": NSNull(), "bounds": NSNull(), "position": NSNull()]

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        // Caption (11) — the design-system content floor for chrome cards, matching
        // the memory card's tappable link rows. caption2 (10) read too small.
        titleLabel.font = NativeTranscriptFont.caption(.medium)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        addSubview(titleLabel)

        domainLabel.translatesAutoresizingMaskIntoConstraints = false
        domainLabel.font = NativeTranscriptFont.caption()
        domainLabel.textColor = Self.muted
        domainLabel.lineBreakMode = .byTruncatingMiddle
        domainLabel.maximumNumberOfLines = 1
        domainLabel.setContentHuggingPriority(.required, for: .horizontal)
        addSubview(domainLabel)

        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: NativeTranscriptFont.captionSize, weight: .semibold))
        chevron.contentTintColor = Self.muted
        chevron.imageScaling = .scaleNone
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        addSubview(chevron)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: leadingInset),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: vPad),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -vPad),

            domainLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 7),
            domainLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            domainLabel.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -8),

            chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            chevron.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor)
        ])

        addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(openSource)))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }

    func configure(title: String, domain: String, url: String) {
        self.url = url
        let displayTitle = title.isEmpty ? domain : title
        titleLabel.stringValue = displayTitle
        // Skip the domain when the title already is the domain (no redundancy).
        domainLabel.stringValue = (displayTitle == domain) ? "" : domain
        domainLabel.isHidden = domainLabel.stringValue.isEmpty
        toolTip = url
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { setHover(true) }
    override func mouseExited(with event: NSEvent) { setHover(false) }

    private func setHover(_ on: Bool) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = on ? Self.hoverFill.cgColor : NSColor.clear.cgColor
        }
        chevron.contentTintColor = on ? Self.accent : Self.muted
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    @objc private func openSource() {
        guard let link = URL(string: url) else { return }
        NSWorkspace.shared.open(link)
    }
}

// MARK: - Flow layout

/// A minimal flow (wrapping) layout container: arranges its item views left to
/// right, wrapping to the next line when the next item would overflow the
/// available width. Items are framed manually; the view drives its own height
/// via a constraint so it measures correctly inside the auto-laid-out tool-group
/// sections stack. Used for the horizontal tool-call list, which wraps to a
/// second line only when many distinct tools don't fit one line.
final class NativeFlowLayoutView: NSView {
    var hSpacing: CGFloat = 12
    var vSpacing: CGFloat = 6
    private var items: [NSView] = []
    private var heightC: NSLayoutConstraint!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        heightC = heightAnchor.constraint(equalToConstant: 0)
        heightC.isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    func setItems(_ views: [NSView]) {
        items.forEach { $0.removeFromSuperview() }
        items = views
        for view in views {
            // We position items by frame, so opt them out of Auto Layout here
            // (their own internal subviews still lay out automatically). Seed the
            // frame to the item's content fitting size *before* flipping
            // `translatesAutoresizingMaskIntoConstraints`: flipping it while the
            // frame is still `.zero` generates `width == 0` / `height == 0`
            // autoresizing constraints that conflict with the item's own content
            // min-width (icon + labels), which AppKit logs-and-breaks on every
            // layout pass — the scroll-time constraint storm. A content-sized seed
            // makes the autoresizing constraints agree with the content.
            view.translatesAutoresizingMaskIntoConstraints = false
            view.frame = CGRect(origin: .zero, size: view.fittingSize)
            view.translatesAutoresizingMaskIntoConstraints = true
            addSubview(view)
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let maxWidth = bounds.width
        guard maxWidth > 0 else { return }
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for view in items {
            let size = view.fittingSize
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + vSpacing
                rowHeight = 0
            }
            view.frame = CGRect(x: x, y: y, width: size.width, height: size.height)
            x += size.width + hSpacing
            rowHeight = max(rowHeight, size.height)
        }
        let total = ceil(y + rowHeight)
        if abs(heightC.constant - total) > 0.5 { heightC.constant = total }
    }
}
