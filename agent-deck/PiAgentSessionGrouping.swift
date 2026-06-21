import Foundation

/// Groups the All-Projects session list by project and computes, per project,
/// which sessions show by default vs. collapse behind a "Show more" affordance.
///
/// Product rule (defaults in `PiAgentSessionGroupingOptions`): within each
/// project, show the five most-recently updated sessions, plus every session
/// updated in the last six hours (which may take the preview over five). The
/// rest hides behind "Show more". Search and the attention-only filter bypass
/// the cap (the user is hunting, so truncation only gets in the way).
///
/// This module is intentionally Foundation-only (no SwiftUI/AppKit) so the
/// preview rule is unit-testable in isolation.
enum PiAgentSessionGrouping {
    /// Identity of the trailing catch-all group that holds sessions whose
    /// `projectPath` no longer resolves to a discovered project.
    static let otherSectionID = "agent-deck.session-group.other"

    /// Split one project's sessions into the preview set and the hidden set.
    ///
    /// - Parameters:
    ///   - sessions: the project's in-scope sessions (order is irrelevant;
    ///     everything is sorted by most-recent update).
    ///   - isExpanded: when `true`, the preview is the entire sorted input and
    ///     nothing is hidden (the user expanded this group).
    ///   - capPreviews: when `false`, previews are uncapped — every session is
    ///     shown. Used while a search query or the attention-only filter is
    ///     active.
    ///   - isWorking: retained for call-site compatibility; recency now drives
    ///     the preview.
    ///   - selectedSessionID: the currently selected session, always shown so
    ///     selection never lands behind a collapsed group.
    ///   - now: the reference instant for the recency windows.
    ///   - options: the tunable thresholds.
    /// - Returns: `all` (the sorted input), `preview` (what to render), and
    ///   `hidden` (what sits behind "Show more"). `preview + hidden == all`.
    static func previewSplit(
        sessions: [PiAgentSessionRecord],
        isExpanded: Bool,
        capPreviews: Bool,
        isWorking: (PiAgentSessionRecord) -> Bool,
        selectedSessionID: UUID?,
        now: Date,
        options: PiAgentSessionGroupingOptions
    ) -> PiAgentSessionPreviewSplit {
        // Use the canonical `sessionListPrecedes` comparator (`updatedAt` at day
        // granularity, then `createdAt` DESC, then id) rather than a bespoke
        // full-timestamp `updatedAt` sort. Comparing `updatedAt` at full
        // granularity makes sessions re-sort on every response within the same
        // day, so a session that's actively streaming jumps to the top of its
        // group continuously — the exact jumble `sessionListPrecedes` was
        // written to prevent. Matching the comparator used by every other sort
        // site (compact strip, store, view model) keeps the list stable and
        // consistent.
        let sorted = sessions.sorted { PiAgentSessionRecord.sessionListPrecedes($0, $1) }

        // Expanded view or uncapped modes show everything.
        if isExpanded || !capPreviews || sorted.isEmpty {
            return PiAgentSessionPreviewSplit(all: sorted, preview: sorted, hidden: [])
        }

        let alwaysCutoff = now.addingTimeInterval(-options.recentAlwaysShownInterval)
        var includedIDs = Set<UUID>()

        // 1. Show the most recently updated sessions, regardless of age.
        for session in sorted.prefix(options.maxRecentPerProject) {
            includedIDs.insert(session.id)
        }

        // 2. Also include everything updated in the always-visible window. This
        //    can take the preview over the five-session cap, matching Codex.
        for session in sorted where session.updatedAt >= alwaysCutoff {
            includedIDs.insert(session.id)
        }

        // 3. Keep the current selection reachable even when it is older than
        //    the preview window; explicit disclosure-collapse still wins later.
        if let selectedSessionID {
            includedIDs.insert(selectedSessionID)
        }

        let preview = sorted.filter { includedIDs.contains($0.id) }
        let hidden = sorted.filter { !includedIDs.contains($0.id) }
        return PiAgentSessionPreviewSplit(all: sorted, preview: preview, hidden: hidden)
    }

    /// Build the full grouped section list from the scoped+filtered sessions.
    ///
    /// Sessions are partitioned by their (resolvable) `projectPath`; sessions
    /// whose path is no longer discovered collect into a trailing "Other"
    /// group. Groups sort alphabetically by repo name (or folder name), with
    /// "Other" always last — so `a-streetcoder/claude-code-meter` sorts as
    /// "claude-code-meter" and `a-streetcoder/agent-deck` sorts as "agent-deck".
    static func sections(
        from sessions: [PiAgentSessionRecord],
        projectByPath: [String: DiscoveredProject],
        expandedProjectIDs: Set<String>,
        collapsedProjectIDs: Set<String>,
        capPreviews: Bool,
        isWorking: (PiAgentSessionRecord) -> Bool,
        selectedSessionID: UUID?,
        now: Date = Date(),
        options: PiAgentSessionGroupingOptions = .default
    ) -> [PiAgentSessionListSection] {
        var byPath: [String: [PiAgentSessionRecord]] = [:]
        var orphans: [PiAgentSessionRecord] = []
        for session in sessions {
            if projectByPath[session.projectPath] != nil {
                byPath[session.projectPath, default: []].append(session)
            } else {
                orphans.append(session)
            }
        }

        var projectSections: [PiAgentSessionListSection] = []
        projectSections.reserveCapacity(byPath.count + (orphans.isEmpty ? 0 : 1))

        for (path, projectSessions) in byPath {
            let project = projectByPath[path]!
            projectSections.append(makeSection(
                id: path,
                title: project.gitHubRemote?.repo ?? project.name,
                subtitle: project.gitHubRemote?.owner,
                iconFileURL: project.iconFileURL,
                fallbackSymbolName: project.fallbackSymbolName,
                assetName: project.projectType.assetName,
                sessions: projectSessions,
                isProjectGroup: true,
                isShowMoreRequested: expandedProjectIDs.contains(path),
                isCollapsed: collapsedProjectIDs.contains(path),
                capPreviews: capPreviews,
                isWorking: isWorking,
                selectedSessionID: selectedSessionID,
                now: now,
                options: options
            ))
        }

        projectSections.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

        if !orphans.isEmpty {
            projectSections.append(makeSection(
                id: otherSectionID,
                title: "Other",
                subtitle: nil,
                iconFileURL: nil,
                fallbackSymbolName: "folder",
                assetName: nil,
                sessions: orphans,
                isProjectGroup: false,
                isShowMoreRequested: expandedProjectIDs.contains(otherSectionID),
                isCollapsed: collapsedProjectIDs.contains(otherSectionID),
                capPreviews: capPreviews,
                isWorking: isWorking,
                selectedSessionID: selectedSessionID,
                now: now,
                options: options
            ))
        }

        return projectSections
    }

    /// The session to make current after `deletedIDs` are removed from the
    /// list the user actually sees (`visibleSessions`, in display order).
    ///
    /// Mail-app semantics applied to the flat grouped list: the row that takes
    /// the deleted set's place is the first sibling BELOW it; if the deleted set
    /// runs to the end of the list, the row immediately ABOVE it becomes current.
    /// If nothing remains, returns `nil` (and the caller clears selection).
    ///
    /// `selectedID` anchors the search — when the user deletes a non-current
    /// row (multi-select delete excluding the current one) the selection should
    /// not move, so the helper only returns a non-nil fallback when the current
    /// selection is among the deleted IDs.
    ///
    /// Why this lives here and not on the store: "next" is a property of the
    /// user's visible grouped order (search/attention filters and collapse
    /// state can hide rows the store still knows about). The store sees the
    /// full flat `sessions` array and would otherwise clamp to the globally
    /// most-recent session, which jumps the transcript to an unrelated chat.
    static func nextSelectionAfterDeletion(
        visibleSessions: [PiAgentSessionRecord],
        deletedIDs: Set<UUID>,
        selectedID: UUID?
    ) -> UUID? {
        // No work to do unless the current selection is being deleted —
        // deleting an unrelated row must not move the active session.
        guard let selectedID, deletedIDs.contains(selectedID) else { return nil }

        // Anchor on the selected row's position in the visible list. From there
        // walk downward for the first surviving "row below"; if the deleted set
        // runs to the end (or the selected row was last/hidden), walk upward
        // for the closest surviving "row above". This handles every deletion
        // shape in ONE pass per direction:
        //   - single selected row deleted → the row immediately below it
        //   - contiguous block including selected → first survivor below the block
        //   - non-contiguous multi-select including selected → the row right
        //     next to the selected one (not far away at the first deleted row)
        //   - selected row was last / not visible → the new last visible row
        //   - nothing survives → nil (caller clears selection)
        let visibleIDs = visibleSessions.map(\.id)
        let anchor = visibleIDs.firstIndex(of: selectedID)

        if let anchor, anchor + 1 < visibleIDs.count {
            for id in visibleIDs[(anchor + 1)...] where !deletedIDs.contains(id) {
                return id
            }
        }
        if let anchor, anchor > 0 {
            for index in stride(from: anchor - 1, through: 0, by: -1) where !deletedIDs.contains(visibleIDs[index]) {
                return visibleIDs[index]
            }
        }
        // Selected row wasn't in the visible list (hidden behind Show more /
        // collapsed) but is being deleted — fall back to the first surviving
        // visible row, or nil if the visible list is also emptied.
        return visibleSessions.first(where: { !deletedIDs.contains($0.id) })?.id
    }

    private static func makeSection(
        id: String,
        title: String,
        subtitle: String?,
        iconFileURL: URL?,
        fallbackSymbolName: String,
        assetName: String?,
        sessions: [PiAgentSessionRecord],
        isProjectGroup: Bool,
        isShowMoreRequested requested: Bool,
        isCollapsed: Bool,
        capPreviews: Bool,
        isWorking: (PiAgentSessionRecord) -> Bool,
        selectedSessionID: UUID?,
        now: Date,
        options: PiAgentSessionGroupingOptions
    ) -> PiAgentSessionListSection {
        // Always evaluate the *collapsed* split so we can tell whether the
        // group actually has anything to collapse (a group with ≤ preview-size
        // sessions has nothing to expand). `requested` only sticks when there
        // is hidden content.
        let split = previewSplit(
            sessions: sessions,
            isExpanded: false,
            capPreviews: capPreviews,
            isWorking: isWorking,
            selectedSessionID: selectedSessionID,
            now: now,
            options: options
        )
        let isShowMore = requested && !split.hidden.isEmpty
        // Items rendered: nothing when disclosure-collapsed; every session when
        // "Show more" is active (most-recent update order, not preview+hidden);
        // otherwise the preview set.
        let items: [PiAgentSessionRecord]
        if isCollapsed {
            items = []
        } else if isShowMore {
            items = split.all
        } else {
            items = split.preview
        }
        let hiddenCount = isCollapsed || isShowMore ? 0 : split.hidden.count
        return PiAgentSessionListSection(
            id: id,
            title: title,
            subtitle: subtitle,
            iconFileURL: iconFileURL,
            fallbackSymbolName: fallbackSymbolName,
            assetName: assetName,
            items: items,
            hiddenCount: hiddenCount,
            isShowMoreActive: isShowMore,
            isCollapsed: isCollapsed,
            totalCount: split.all.count,
            isProjectGroup: isProjectGroup
        )
    }
}

/// Tunable thresholds for per-project session previewing. Defaults encode the
/// shipped product rule; kept as a type so tests and future tuning have one
/// knob to turn.
struct PiAgentSessionGroupingOptions: Equatable, Sendable {
    /// Sessions updated within this interval of `now` are always shown, even
    /// when that takes the preview over `maxRecentPerProject`.
    var recentAlwaysShownInterval: TimeInterval = 21_600       // 6 hours
    /// Kept for source compatibility with older tests/callers; no longer used
    /// by the default preview rule.
    var recentBucketInterval: TimeInterval = 86_400            // unused
    /// Maximum most-recent sessions shown per project before the rest collapse
    /// behind "Show more". The six-hour always-visible window can exceed this.
    var maxRecentPerProject: Int = 5

    static let `default` = PiAgentSessionGroupingOptions()
}

/// Result of `PiAgentSessionGrouping.previewSplit`. `preview + hidden == all`,
/// and all three are in most-recent update order.
struct PiAgentSessionPreviewSplit: Equatable {
    let all: [PiAgentSessionRecord]
    let preview: [PiAgentSessionRecord]
    let hidden: [PiAgentSessionRecord]
}

/// One section of the grouped session list: a project (or the catch-all
/// "Other") plus the sessions to render for it. Plain `Equatable` data (no
/// SwiftUI) so `SessionListContent`'s `.equatable()` gate can compare it
/// cheaply and skip rebuilds on streaming pulses.
struct PiAgentSessionListSection: Equatable, Identifiable {
    /// Stable identity: the project path, or `PiAgentSessionGrouping.otherSectionID`.
    let id: String
    /// Header title — the GitHub repo name, or the folder name; "Other" for the
    /// catch-all.
    let title: String
    /// Muted header subtitle — the GitHub owner, when known.
    let subtitle: String?
    /// Custom project artwork, forwarded to `ProjectIconView`.
    let iconFileURL: URL?
    /// SF Symbol fallback for `ProjectIconView`.
    let fallbackSymbolName: String
    /// Asset-catalog artwork name for `ProjectIconView` (`projectType.assetName`).
    let assetName: String?
    /// Sessions rendered in this section, in display order. Empty when the
    /// group is disclosure-collapsed; otherwise the preview set, or every
    /// session when "Show more" is active.
    let items: [PiAgentSessionRecord]
    /// Sessions hidden behind "Show more". `0` when collapsed, when "Show
    /// more" is already active, or when nothing is hidden — in which case no
    /// affordance renders.
    let hiddenCount: Int
    /// Whether "Show more" is active for this group (drives "Show less").
    /// Only true when the group has collapsible content.
    let isShowMoreActive: Bool
    /// Whether the group is disclosure-collapsed to just its header (no
    /// sessions rendered). Drives the header chevron direction.
    let isCollapsed: Bool
    /// Total sessions belonging to this group (rendered + hidden).
    let totalCount: Int
    /// True for real discovered projects; false for the catch-all "Other"
    /// group. The header's "new session" affordance only renders for real
    /// projects.
    let isProjectGroup: Bool
}
