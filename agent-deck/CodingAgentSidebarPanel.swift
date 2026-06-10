import SwiftUI

/// Single definition of what "session matches the search query" means, shared
/// by the expanded panel's full list and the collapsed panel's recents so the
/// toolbar search filters both identically.
extension PiAgentSessionRecord {
    func matchesSessionSearch(_ query: String) -> Bool {
        [
            title,
            projectName,
            projectPath,
            repository ?? "",
            issueNumber.map(String.init) ?? "",
            lastSummary ?? ""
        ]
        .joined(separator: " ")
        .localizedCaseInsensitiveContains(query)
    }
}

/// Header row shared by both states of the Coding Agent pull-up panel: the
/// project selector (icon + name + picker glyph opening the project popover),
/// live status badges, a per-state trailing slot (new-session controls,
/// delete) and the expand/collapse chevron. The whole row is tappable; inner
/// buttons take gesture priority so their own actions still win.
struct CodingAgentPanelHeader<Trailing: View>: View {
    let viewModel: AppViewModel
    let isExpanded: Bool
    let onToggle: () -> Void
    let projects: [DiscoveredProject]
    let selectedProject: DiscoveredProject?
    let selectedProjectPath: String?
    @Binding var projectFilterText: String
    let isSearchDebouncing: Bool
    let onSelectProject: (DiscoveredProject?) -> Void
    @ViewBuilder var trailing: Trailing

    @State private var isProjectPickerPresented = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // 30 matches the visible height of the title+subtitle block beside
            // it (34 overhung the text on both ends) and the 30pt round
            // controls at the row's trailing edge.
            ProjectIconView(
                imageURL: selectedProject?.iconFileURL,
                symbolName: selectedProject?.fallbackSymbolName ?? "square.grid.2x2",
                size: 30,
                assetName: selectedProject?.projectType.assetName
            )

            Button {
                isProjectPickerPresented.toggle()
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .center, spacing: 5) {
                        Text(selectedProjectTitle)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    if selectedProject != nil {
                        Text(selectedProjectSubtitle)
                            .font(.callout)
                            .fontWeight(.regular)
                            .foregroundStyle(AppTheme.mutedText)
                            .lineLimit(1)
                            .fontWidth(.compressed)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Choose project")
            .accessibilityLabel("Choose project")
            .accessibilityHint("Opens the project picker")
            .popover(isPresented: $isProjectPickerPresented, arrowEdge: .bottom) {
                ProjectPickerPopover(
                    projects: projects,
                    selectedProjectPath: selectedProjectPath,
                    filterText: $projectFilterText,
                    isSearchDebouncing: isSearchDebouncing,
                    onSelectProject: { project in
                        onSelectProject(project)
                        isProjectPickerPresented = false
                    }
                )
            }

            CodingAgentStatusBadges(viewModel: viewModel)

            Spacer(minLength: 8)

            trailing

            AppCircleIconButton(
                style: .neutral,
                size: 30,
                help: isExpanded ? "Collapse to navigation" : "Show all sessions",
                action: onToggle
            ) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
            }
            .accessibilityLabel(isExpanded ? "Collapse sessions" : "Expand sessions")
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
    }

    private var selectedProjectTitle: String {
        if selectedProject == nil && selectedProjectPath == nil {
            return "All Projects"
        }
        if let remote = selectedProject?.gitHubRemote {
            return remote.repo
        }
        if let selectedProject {
            return selectedProject.name
        }
        if let selectedProjectPath {
            return URL(fileURLWithPath: selectedProjectPath).lastPathComponent
        }
        return "Choose Project"
    }

    private var selectedProjectSubtitle: String {
        if let remote = selectedProject?.gitHubRemote {
            return remote.owner
        }
        return selectedProject?.path ?? selectedProjectPath ?? ""
    }
}

/// The ONLY sidebar view that reads the session-derived counts: they touch
/// `store.sessions`, which mutates at streaming cadence, so confining the read
/// to this leaf keeps the streaming pulse off the nav list and the badge card.
struct CodingAgentStatusBadges: View {
    let viewModel: AppViewModel

    var body: some View {
        let runningCount = viewModel.piAgentRunningSessionCount
        let attentionCount = viewModel.piAgentNeedsAttentionCount
        if runningCount > 0 || attentionCount > 0 {
            HStack(spacing: 8) {
                if runningCount > 0 {
                    PiAgentTypingIndicator()
                }
                if attentionCount > 0 {
                    Text(attentionCount > 99 ? "99+" : "\(attentionCount)")
                        .font(.system(size: 10, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, attentionCount > 9 ? 5 : 4)
                        .frame(minWidth: 14, minHeight: 14)
                        .background(Capsule(style: .continuous).fill(Color.red))
                        .accessibilityLabel("\(attentionCount) session\(attentionCount == 1 ? "" : "s") waiting")
                }
            }
            .help(helpText(running: runningCount, attention: attentionCount))
        }
    }

    private func helpText(running: Int, attention: Int) -> String {
        let waitingText = attention == 1 ? "1 session waiting" : "\(attention) sessions waiting"
        let runningText = running == 1 ? "1 session running" : "\(running) sessions running"
        if attention > 0 && running > 0 {
            return "\(waitingText), \(runningText)"
        }
        return attention > 0 ? waitingText : runningText
    }
}

/// New-session controls shared by the collapsed and expanded panel headers:
/// the glass split capsule when Deck agents are enabled, otherwise the project
/// picker `+` (no scoped project) or the plain `+`.
struct CodingAgentNewSessionControls: View {
    let viewModel: AppViewModel

    var body: some View {
        if viewModel.appSettings.nativeSubagentsEnabledForNewSessions {
            PiAgentNewSessionSplitButton(
                viewModel: viewModel,
                projects: orderedProjects,
                selectedProject: viewModel.selectedDiscoveredProject,
                onNewSession: { viewModel.createPiAgentDraftForSelectedProject() },
                onNewSessionForProject: { viewModel.createPiAgentDraft(for: $0) }
            )
        } else if viewModel.selectedDiscoveredProject == nil {
            PiAgentAddSessionMenuButton(
                projects: orderedProjects,
                selectedProject: viewModel.selectedDiscoveredProject,
                action: { viewModel.createPiAgentDraftForSelectedProject() },
                onSelectProject: { viewModel.createPiAgentDraft(for: $0) }
            )
        } else {
            PiAgentAddSessionButton(action: { viewModel.createPiAgentDraftForSelectedProject() })
        }
    }

    private var orderedProjects: [DiscoveredProject] {
        viewModel.enabledProjects.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

/// Collapsed state of the Coding Agent pull-up panel: header + the most recent
/// sessions inline, so resuming a chat is one click without expanding. Lives at
/// the bottom of the nav sidebar, just above the project/GitHub card.
struct CodingAgentCollapsedPanel: View {
    let viewModel: AppViewModel
    let store: PiAgentSessionStore
    let projects: [DiscoveredProject]
    let selectedProject: DiscoveredProject?
    @Binding var projectFilterText: String
    let isSearchDebouncing: Bool
    let onSelectProject: (DiscoveredProject?) -> Void
    /// The same toolbar search the expanded list filters on, so searching
    /// narrows the recents too.
    let sessionSearchText: String

    /// Cached so `body` never reads `store.sessions` directly — `touchSession`
    /// mutates that array many times per second during streaming. Rebuilt only
    /// on the non-streaming triggers that actually change the list, mirroring
    /// the expanded panel's `cachedVisibleSessions`.
    @State private var recentSessions: [PiAgentSessionRecord] = []

    private static let maxRecents = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CodingAgentPanelHeader(
                viewModel: viewModel,
                isExpanded: false,
                onToggle: { viewModel.openPiAgentScreen() },
                projects: projects,
                selectedProject: selectedProject,
                selectedProjectPath: viewModel.selectedProjectPath,
                projectFilterText: $projectFilterText,
                isSearchDebouncing: isSearchDebouncing,
                onSelectProject: onSelectProject
            ) {
                CodingAgentNewSessionControls(viewModel: viewModel)
            }
            // 8 (card) + 6 here = a 14pt content inset, matching the account
            // card at the top of the sidebar.
            .padding(.horizontal, 6)
            .padding(.top, 2)

            if !recentSessions.isEmpty {
                CodingAgentRecentList(
                    sessions: recentSessions,
                    selectedSessionID: store.selectedSessionID,
                    isAgentSelected: viewModel.selectedSidebarItem == .agent,
                    workingSessionIDs: workingRecentSessionIDs,
                    onSelect: { viewModel.selectPiAgentSession($0) }
                )
                .equatable()
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .appContentSurface(cornerRadius: 16)
        .onAppear(perform: rebuildRecents)
        .onChange(of: store.sessionListRevision) { _, _ in rebuildRecents() }
        .onChange(of: viewModel.selectedProjectPath) { _, _ in rebuildRecents() }
        .onChange(of: sessionSearchText) { _, _ in rebuildRecents() }
        .onChange(of: viewModel.showPiAgentAttentionOnly) { _, _ in rebuildRecents() }
    }

    private var workingRecentSessionIDs: Set<UUID> {
        Set(recentSessions.filter { viewModel.piAgentSessionIsWorking($0) }.map(\.id))
    }

    private func rebuildRecents() {
        var scoped: [PiAgentSessionRecord]
        if let path = viewModel.selectedProjectPath {
            scoped = store.sessions.filter { $0.projectPath == path }
        } else {
            scoped = store.sessions
        }
        if viewModel.showPiAgentAttentionOnly {
            scoped = scoped.filter(\.needsAttention)
        }
        let query = sessionSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            scoped = scoped.filter { $0.matchesSessionSearch(query) }
        }
        let next = Array(
            scoped
                .sorted { PiAgentSessionRecord.sessionListPrecedes($0, $1) }
                .prefix(Self.maxRecents)
        )
        if next != recentSessions { recentSessions = next }
    }
}

/// Equatable boundary for the recents — the collapsed panel's body re-evaluates
/// on streaming-adjacent triggers (working IDs, project map churn), and this
/// keeps those pulses from re-laying-out the rows unless something a row
/// actually shows changed. Mirrors `SessionListContent`'s discipline.
private struct CodingAgentRecentList: View, Equatable {
    let sessions: [PiAgentSessionRecord]
    let selectedSessionID: UUID?
    let isAgentSelected: Bool
    let workingSessionIDs: Set<UUID>
    let onSelect: (UUID) -> Void

    static func == (lhs: CodingAgentRecentList, rhs: CodingAgentRecentList) -> Bool {
        lhs.sessions == rhs.sessions
            && lhs.selectedSessionID == rhs.selectedSessionID
            && lhs.isAgentSelected == rhs.isAgentSelected
            && lhs.workingSessionIDs == rhs.workingSessionIDs
    }

    var body: some View {
        VStack(spacing: 1) {
            ForEach(sessions) { session in
                CodingAgentRecentRow(
                    session: session,
                    isSelected: isAgentSelected && selectedSessionID == session.id,
                    isRunning: workingSessionIDs.contains(session.id),
                    onSelect: { onSelect(session.id) }
                )
                .equatable()
            }
        }
    }
}

/// Compact one-line session row for the collapsed panel: title and a live
/// status slot (typing dots while running, bell when waiting). No project icon
/// — the panel header's project selector already says where you are.
struct CodingAgentRecentRow: View, Equatable {
    let session: PiAgentSessionRecord
    let isSelected: Bool
    let isRunning: Bool
    let onSelect: () -> Void

    // Closures intentionally excluded: when the value inputs match, the retained
    // instance's closure captured the same session id, so it stays correct.
    static func == (lhs: CodingAgentRecentRow, rhs: CodingAgentRecentRow) -> Bool {
        lhs.session == rhs.session
            && lhs.isSelected == rhs.isSelected
            && lhs.isRunning == rhs.isRunning
    }

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Text(session.displayTitle)
                    .font(AppTheme.Font.footnote.weight(.medium))
                    .fontWidth(.expanded)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 6)

                if isRunning {
                    PiAgentTypingIndicator()
                } else if session.needsAttention {
                    Image(systemName: "bell.fill")
                        .font(AppTheme.Font.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.brandAccent)
                        .help("Pi Agent finished and needs review")
                        .accessibilityLabel("Needs review")
                }
            }
            // 8 (card) + 6 here = 14pt content inset, aligned with the header.
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(rowFill)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(session.displayTitle)
    }

    private var rowFill: Color {
        if isSelected {
            return AppTheme.brandAccent.opacity(0.22)
        }
        if isHovering {
            return Color.primary.opacity(0.06)
        }
        return .clear
    }
}
