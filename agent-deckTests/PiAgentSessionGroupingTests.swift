import XCTest
@testable import agent_deck

@MainActor
final class PiAgentSessionGroupingTests: XCTestCase {

    /// Fixed reference instant so recency windows are deterministic.
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - previewSplit

    func testRecentPreviewCappedAtFiveWhenAllOld() throws {
        // 8 sessions outside the 6-hour always-shown window → 5 newest shown,
        // 3 hidden behind Show more.
        let sessions = try (0..<8).map { i in
            try makeSession(title: "s\(i)", updatedAt: now.addingTimeInterval(-Double(30_000 + i)))
        }
        let split = PiAgentSessionGrouping.previewSplit(
            sessions: sessions, isExpanded: false, capPreviews: true,
            isWorking: { _ in false }, selectedSessionID: nil, now: now, options: .default)
        XCTAssertEqual(split.preview.count, 5)
        XCTAssertEqual(split.hidden.count, 3)
    }

    func testSixHourWindowAlwaysShownAndCanExceedFive() throws {
        let recent = try (0..<8).map { i in
            try makeSession(title: "r\(i)", updatedAt: now.addingTimeInterval(-Double(3600 + i)))
        }
        let old = try (0..<3).map { i in
            try makeSession(title: "old\(i)", updatedAt: now.addingTimeInterval(-Double(30_000 + i)))
        }
        let split = PiAgentSessionGrouping.previewSplit(
            sessions: recent + old, isExpanded: false, capPreviews: true,
            isWorking: { _ in false }, selectedSessionID: nil, now: now, options: .default)
        XCTAssertEqual(split.preview.count, 8)
        XCTAssertEqual(split.hidden.count, 3)
    }

    func testWorkingDoesNotOverrideRecencyRule() throws {
        let oldWorking = try makeSession(title: "working", updatedAt: now.addingTimeInterval(-100_000), status: .running)
        let newer = try (0..<5).map { i in
            try makeSession(title: "newer\(i)", updatedAt: now.addingTimeInterval(-Double(30_000 + i)))
        }
        let split = PiAgentSessionGrouping.previewSplit(
            sessions: [oldWorking] + newer, isExpanded: false, capPreviews: true,
            isWorking: { $0.status == .running }, selectedSessionID: nil, now: now, options: .default)
        XCTAssertFalse(split.preview.contains { $0.title == "working" })
    }

    func testSelectedSessionAlwaysShown() throws {
        // An old session that would otherwise be hidden is surfaced because it
        // is the currently selected one.
        let selected = try makeSession(title: "selected", updatedAt: now.addingTimeInterval(-500_000))
        let bucket = try (0..<8).map { i in
            try makeSession(title: "s\(i)", updatedAt: now.addingTimeInterval(-3600))
        }
        let split = PiAgentSessionGrouping.previewSplit(
            sessions: [selected] + bucket, isExpanded: false, capPreviews: true,
            isWorking: { _ in false }, selectedSessionID: selected.id, now: now, options: .default)
        XCTAssertTrue(split.preview.contains { $0.id == selected.id })
        XCTAssertFalse(split.hidden.contains { $0.id == selected.id })
    }

    func testFloorShowsMostRecentWhenAllOld() throws {
        // Fewer than 5 old sessions are all shown.
        let sessions = try (0..<4).map { i in
            try makeSession(title: "old\(i)", updatedAt: now.addingTimeInterval(-Double(200_000 + i * 1000)))
        }
        let split = PiAgentSessionGrouping.previewSplit(
            sessions: sessions, isExpanded: false, capPreviews: true,
            isWorking: { _ in false }, selectedSessionID: nil, now: now, options: .default)
        XCTAssertEqual(split.preview.count, 4)
        XCTAssertEqual(split.hidden.count, 0)
    }

    func testPreviewUnionedWithHiddenEqualsAll() throws {
        let sessions = try (0..<10).map { i in
            try makeSession(title: "s\(i)", updatedAt: now.addingTimeInterval(-Double(3600 + i * 5000)))
        }
        let split = PiAgentSessionGrouping.previewSplit(
            sessions: sessions, isExpanded: false, capPreviews: true,
            isWorking: { _ in false }, selectedSessionID: nil, now: now, options: .default)
        let previewIDs = Set(split.preview.map(\.id))
        let hiddenIDs = Set(split.hidden.map(\.id))
        XCTAssertEqual(previewIDs.intersection(hiddenIDs), [])
        XCTAssertEqual(previewIDs.union(hiddenIDs), Set(split.all.map(\.id)))
    }

    // MARK: - previewSplit edge modes

    func testExpandedShowsAll() throws {
        let sessions = try (0..<8).map { i in
            try makeSession(title: "s\(i)", updatedAt: now.addingTimeInterval(-3600))
        }
        let split = PiAgentSessionGrouping.previewSplit(
            sessions: sessions, isExpanded: true, capPreviews: true,
            isWorking: { _ in false }, selectedSessionID: nil, now: now, options: .default)
        XCTAssertEqual(split.preview.count, 8)
        XCTAssertTrue(split.hidden.isEmpty)
    }

    func testCapPreviewsFalseShowsAll() throws {
        let sessions = try (0..<8).map { i in
            try makeSession(title: "s\(i)", updatedAt: now.addingTimeInterval(-3600))
        }
        let split = PiAgentSessionGrouping.previewSplit(
            sessions: sessions, isExpanded: false, capPreviews: false,
            isWorking: { _ in false }, selectedSessionID: nil, now: now, options: .default)
        XCTAssertEqual(split.preview.count, 8)
        XCTAssertTrue(split.hidden.isEmpty)
    }

    // MARK: - sections

    func testGroupsSortedAlphabeticallyByRepoName() throws {
        // owner/repo → sorts by repo. "agent-deck" < "claude-code-meter".
        let deck = try makeProject(path: "/p/deck", repo: "agent-deck", owner: "a-streetcoder")
        let meter = try makeProject(path: "/p/meter", repo: "claude-code-meter", owner: "a-streetcoder")
        let projectByPath = [deck.path: deck, meter.path: meter]
        let sessions = [
            try makeSession(title: "m1", updatedAt: now, projectPath: meter.path),
            try makeSession(title: "d1", updatedAt: now, projectPath: deck.path)
        ]
        let sections = PiAgentSessionGrouping.sections(
            from: sessions, projectByPath: projectByPath, expandedProjectIDs: [],
            collapsedProjectIDs: [],
            capPreviews: true, isWorking: { _ in false }, selectedSessionID: nil, now: now)
        XCTAssertEqual(sections.map(\.title), ["agent-deck", "claude-code-meter"])
        XCTAssertEqual(sections.first?.subtitle, "a-streetcoder")
        XCTAssertTrue(sections.allSatisfy { $0.isProjectGroup })
    }

    func testOrphansCollectIntoTrailingOtherGroup() throws {
        let deck = try makeProject(path: "/p/deck", repo: "agent-deck", owner: "a-streetcoder")
        let sessions = [
            try makeSession(title: "d1", updatedAt: now, projectPath: deck.path),
            try makeSession(title: "orphan", updatedAt: now, projectPath: "/p/ghost")
        ]
        let sections = PiAgentSessionGrouping.sections(
            from: sessions, projectByPath: [deck.path: deck], expandedProjectIDs: [],
            collapsedProjectIDs: [],
            capPreviews: true, isWorking: { _ in false }, selectedSessionID: nil, now: now)
        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections.last?.id, PiAgentSessionGrouping.otherSectionID)
        XCTAssertEqual(sections.last?.title, "Other")
        XCTAssertFalse(sections.last?.isProjectGroup ?? true)
    }

    func testShowMoreRevealsAllAndReportsTotalCount() throws {
        let deck = try makeProject(path: "/p/deck", repo: "agent-deck", owner: "a-streetcoder")
        let sessions = try (0..<8).map { i in
            try makeSession(title: "s\(i)", updatedAt: now.addingTimeInterval(-Double(30_000 + i)), projectPath: deck.path)
        }
        let sections = PiAgentSessionGrouping.sections(
            from: sessions, projectByPath: [deck.path: deck],
            expandedProjectIDs: [deck.path], collapsedProjectIDs: [],
            capPreviews: true, isWorking: { _ in false }, selectedSessionID: nil, now: now)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections.first?.items.count, 8)
        XCTAssertEqual(sections.first?.hiddenCount, 0)
        XCTAssertEqual(sections.first?.totalCount, 8)
        XCTAssertTrue(sections.first?.isShowMoreActive ?? false)
    }

    func testCollapsedGroupRendersZeroItems() throws {
        let deck = try makeProject(path: "/p/deck", repo: "agent-deck", owner: "a-streetcoder")
        let sessions = try (0..<8).map { i in
            try makeSession(title: "s\(i)", updatedAt: now.addingTimeInterval(-Double(30_000 + i)), projectPath: deck.path)
        }
        let sections = PiAgentSessionGrouping.sections(
            from: sessions, projectByPath: [deck.path: deck],
            expandedProjectIDs: [], collapsedProjectIDs: [deck.path],
            capPreviews: true, isWorking: { _ in false }, selectedSessionID: nil, now: now)
        XCTAssertEqual(sections.first?.items.count, 0)
        XCTAssertEqual(sections.first?.hiddenCount, 0)
        XCTAssertEqual(sections.first?.totalCount, 8)
        XCTAssertTrue(sections.first?.isCollapsed ?? false)
    }

    func testCollapsedGroupHidesBeyondFive() throws {
        let deck = try makeProject(path: "/p/deck", repo: "agent-deck", owner: "a-streetcoder")
        let sessions = try (0..<8).map { i in
            try makeSession(title: "s\(i)", updatedAt: now.addingTimeInterval(-Double(30_000 + i)), projectPath: deck.path)
        }
        let sections = PiAgentSessionGrouping.sections(
            from: sessions, projectByPath: [deck.path: deck], expandedProjectIDs: [],
            collapsedProjectIDs: [],
            capPreviews: true, isWorking: { _ in false }, selectedSessionID: nil, now: now)
        XCTAssertEqual(sections.first?.items.count, 5)
        XCTAssertEqual(sections.first?.hiddenCount, 3)
        XCTAssertFalse(sections.first?.isShowMoreActive ?? true)
    }

    func testExplicitCollapseHidesSelectedSessionButKeepsCount() throws {
        // Explicit disclosure-collapse wins: the group renders header-only even
        // if it contains the current selection. The total count remains correct
        // so the user can expand it from the header.
        let deck = try makeProject(path: "/p/deck", repo: "agent-deck", owner: "a-streetcoder")
        let sessions = try (0..<4).map { i in
            try makeSession(title: "s\(i)", updatedAt: now.addingTimeInterval(-3600), projectPath: deck.path)
        }
        let selected = sessions[3]
        let sections = PiAgentSessionGrouping.sections(
            from: sessions, projectByPath: [deck.path: deck],
            expandedProjectIDs: [], collapsedProjectIDs: [deck.path],
            capPreviews: true, isWorking: { _ in false },
            selectedSessionID: selected.id, now: now)
        XCTAssertEqual(sections.first?.items.count, 0)
        XCTAssertEqual(sections.first?.totalCount, 4)
    }

    // MARK: - Active / Recent section

    /// Multi-project browsing: live sessions (updated inside the 30-minute
    /// window) are lifted into a cross-project "Active / Recent" section pinned
    /// above the project groups, and deduped out of their own project groups so
    /// each session renders in exactly one place.
    func testActiveRecentSurfacedAboveProjectGroupsAndDeduped() throws {
        let deck = try makeProject(path: "/p/deck", repo: "agent-deck", owner: "a-streetcoder")
        let meter = try makeProject(path: "/p/meter", repo: "claude-code-meter", owner: "a-streetcoder")
        let projectByPath = [deck.path: deck, meter.path: meter]
        let deckLive = try makeSession(title: "deck-live", updatedAt: now.addingTimeInterval(-60), projectPath: deck.path)
        let deckOld = try makeSession(title: "deck-old", updatedAt: now.addingTimeInterval(-100_000), projectPath: deck.path)
        let meterLive = try makeSession(title: "meter-live", updatedAt: now.addingTimeInterval(-120), projectPath: meter.path)
        let meterOld = try makeSession(title: "meter-old", updatedAt: now.addingTimeInterval(-100_000), projectPath: meter.path)
        let sections = PiAgentSessionGrouping.sections(
            from: [deckLive, deckOld, meterLive, meterOld], projectByPath: projectByPath,
            expandedProjectIDs: [], collapsedProjectIDs: [],
            capPreviews: true, includeActiveRecent: true,
            isWorking: { _ in false }, selectedSessionID: nil, now: now)
        XCTAssertEqual(sections.first?.id, PiAgentSessionGrouping.activeRecentSectionID)
        XCTAssertEqual(sections.first?.title, "Recent")
        XCTAssertEqual(Set(sections.first!.items.map(\.id)), [deckLive.id, meterLive.id])
        // Live sessions are deduped out of their own project groups.
        XCTAssertEqual(sections.first { $0.id == deck.path }?.items.map(\.id), [deckOld.id])
        XCTAssertEqual(sections.first { $0.id == meter.path }?.items.map(\.id), [meterOld.id])
    }

    /// A running session is always surfaced even when its timestamp is far
    /// outside the live window, and the header reads "Active".
    func testActiveRecentIncludesRunningEvenWhenOld() throws {
        let deck = try makeProject(path: "/p/deck", repo: "agent-deck", owner: "a-streetcoder")
        let meter = try makeProject(path: "/p/meter", repo: "claude-code-meter", owner: "a-streetcoder")
        let projectByPath = [deck.path: deck, meter.path: meter]
        let running = try makeSession(title: "running", updatedAt: now.addingTimeInterval(-1_000_000), status: .running, projectPath: deck.path)
        let other = try makeSession(title: "other", updatedAt: now.addingTimeInterval(-1_000_000), projectPath: meter.path)
        let sections = PiAgentSessionGrouping.sections(
            from: [running, other], projectByPath: projectByPath,
            expandedProjectIDs: [], collapsedProjectIDs: [],
            capPreviews: true, includeActiveRecent: true,
            isWorking: { $0.status == .running }, selectedSessionID: nil, now: now)
        XCTAssertEqual(sections.first?.id, PiAgentSessionGrouping.activeRecentSectionID)
        XCTAssertEqual(sections.first?.title, "Active")
        XCTAssertEqual(Set(sections.first!.items.map(\.id)), [running.id])
        // The running session renders ONLY in Active / Recent. Its project group
        // is absent here because deck had no other sessions to show after the
        // lift; what matters is it isn't duplicated elsewhere.
        XCTAssertNil(sections.first { $0.id != PiAgentSessionGrouping.activeRecentSectionID && $0.items.contains { $0.id == running.id } })
        XCTAssertEqual(sections.first { $0.id == meter.path }?.items.map(\.id), [other.id])
    }

    /// `includeActiveRecent == false` (search / attention filter / default) →
    /// no section, and sessions stay in their project groups (no dedup).
    func testActiveRecentOmittedWhenNotBrowsing() throws {
        let deck = try makeProject(path: "/p/deck", repo: "agent-deck", owner: "a-streetcoder")
        let meter = try makeProject(path: "/p/meter", repo: "claude-code-meter", owner: "a-streetcoder")
        let projectByPath = [deck.path: deck, meter.path: meter]
        let live = try makeSession(title: "live", updatedAt: now, projectPath: deck.path)
        let other = try makeSession(title: "other", updatedAt: now, projectPath: meter.path)
        let sections = PiAgentSessionGrouping.sections(
            from: [live, other], projectByPath: projectByPath,
            expandedProjectIDs: [], collapsedProjectIDs: [],
            capPreviews: true, includeActiveRecent: false,
            isWorking: { _ in false }, selectedSessionID: nil, now: now)
        XCTAssertFalse(sections.contains { $0.id == PiAgentSessionGrouping.activeRecentSectionID })
        XCTAssertEqual(sections.first { $0.id == deck.path }?.items.map(\.id), [live.id])
    }

    /// Single-project setup → no Active/Recent (it would just fragment that
    /// project's list); the project keeps its full preview.
    func testActiveRecentOmittedForSingleProjectSetup() throws {
        let deck = try makeProject(path: "/p/deck", repo: "agent-deck", owner: "a-streetcoder")
        let live = try makeSession(title: "live", updatedAt: now, projectPath: deck.path)
        let old = try makeSession(title: "old", updatedAt: now.addingTimeInterval(-100_000), projectPath: deck.path)
        let sections = PiAgentSessionGrouping.sections(
            from: [live, old], projectByPath: [deck.path: deck],
            expandedProjectIDs: [], collapsedProjectIDs: [],
            capPreviews: true, includeActiveRecent: true,
            isWorking: { _ in false }, selectedSessionID: nil, now: now)
        XCTAssertFalse(sections.contains { $0.id == PiAgentSessionGrouping.activeRecentSectionID })
        XCTAssertEqual(sections.first?.items.count, 2)
    }

    /// Multi-project but nothing live → no section (and nothing deduped).
    func testActiveRecentOmittedWhenNothingLive() throws {
        let deck = try makeProject(path: "/p/deck", repo: "agent-deck", owner: "a-streetcoder")
        let meter = try makeProject(path: "/p/meter", repo: "claude-code-meter", owner: "a-streetcoder")
        let projectByPath = [deck.path: deck, meter.path: meter]
        let a = try makeSession(title: "a", updatedAt: now.addingTimeInterval(-100_000), projectPath: deck.path)
        let b = try makeSession(title: "b", updatedAt: now.addingTimeInterval(-100_000), projectPath: meter.path)
        let sections = PiAgentSessionGrouping.sections(
            from: [a, b], projectByPath: projectByPath,
            expandedProjectIDs: [], collapsedProjectIDs: [],
            capPreviews: true, includeActiveRecent: true,
            isWorking: { _ in false }, selectedSessionID: nil, now: now)
        XCTAssertFalse(sections.contains { $0.id == PiAgentSessionGrouping.activeRecentSectionID })
        XCTAssertEqual(sections.first { $0.id == deck.path }?.items.map(\.id), [a.id])
    }

    // MARK: - nextSelectionAfterDeletion

    /// Three sessions, delete the middle (current) one → the row below it wins.
    func testNextSelectionPicksRowBelowDeletedSelection() throws {
        let sessions = try (0..<3).map { i in
            try makeSession(title: "s\(i)", updatedAt: now.addingTimeInterval(-Double(3600 * i)))
        }
        let next = PiAgentSessionGrouping.nextSelectionAfterDeletion(
            visibleSessions: sessions, deletedIDs: [sessions[1].id], selectedID: sessions[1].id)
        XCTAssertEqual(next, sessions[2].id)
    }

    /// Delete the LAST (current) row → fall back to the row above it.
    func testNextSelectionFallsBackToRowAboveWhenDeletingLast() throws {
        let sessions = try (0..<3).map { i in
            try makeSession(title: "s\(i)", updatedAt: now.addingTimeInterval(-Double(3600 * i)))
        }
        let next = PiAgentSessionGrouping.nextSelectionAfterDeletion(
            visibleSessions: sessions, deletedIDs: [sessions[2].id], selectedID: sessions[2].id)
        XCTAssertEqual(next, sessions[1].id)
    }

    /// Delete the only visible session → nil so the caller clears selection.
    func testNextSelectionReturnsNilWhenNoSurvivors() throws {
        let only = try makeSession(title: "only", updatedAt: now)
        let next = PiAgentSessionGrouping.nextSelectionAfterDeletion(
            visibleSessions: [only], deletedIDs: [only.id], selectedID: only.id)
        XCTAssertNil(next)
    }

    /// Delete a NON-current row → selection must not move (returns nil), even
    /// when other rows are deleted alongside it.
    func testNextSelectionNilWhenCurrentSelectionSurvives() throws {
        let sessions = try (0..<4).map { i in
            try makeSession(title: "s\(i)", updatedAt: now.addingTimeInterval(-Double(3600 * i)))
        }
        // Delete rows 0 and 2 but the current selection is row 1.
        let next = PiAgentSessionGrouping.nextSelectionAfterDeletion(
            visibleSessions: sessions, deletedIDs: [sessions[0].id, sessions[2].id],
            selectedID: sessions[1].id)
        XCTAssertNil(next)
    }

    /// Multi-select delete of a NON-CONTIGUOUS set including the selected row
    /// (e.g. delete rows {0,2} where the current selection is row 2): the row
    /// immediately below the selected one wins, NOT a survivor of row 0's gap.
    func testNextSelectionAnchorsOnSelectedRowNotFirstDeleted() throws {
        let sessions = try (0..<5).map { i in
            try makeSession(title: "s\(i)", updatedAt: now.addingTimeInterval(-Double(3600 * i)))
        }
        // Delete row 0 and row 2 (the current selection). The natural target is
        // the row right after the selected one (row 3), not row 1.
        let next = PiAgentSessionGrouping.nextSelectionAfterDeletion(
            visibleSessions: sessions, deletedIDs: [sessions[0].id, sessions[2].id],
            selectedID: sessions[2].id)
        XCTAssertEqual(next, sessions[3].id)
    }

    /// Contiguous block including the selected row → first survivor below the block.
    func testNextSelectionFindsFirstSurvivorAfterContiguousBlock() throws {
        let sessions = try (0..<6).map { i in
            try makeSession(title: "s\(i)", updatedAt: now.addingTimeInterval(-Double(3600 * i)))
        }
        // Delete rows 2,3,4 with the current selection at row 3.
        let deletedIDs: Set<UUID> = [sessions[2].id, sessions[3].id, sessions[4].id]
        let next = PiAgentSessionGrouping.nextSelectionAfterDeletion(
            visibleSessions: sessions, deletedIDs: deletedIDs,
            selectedID: sessions[3].id)
        XCTAssertEqual(next, sessions[5].id)
    }

    /// Contiguous block including the selected row that runs to the END of the
    /// list → first survivor ABOVE the block.
    func testNextSelectionFallsUpwardWhenBlockRunsToEnd() throws {
        let sessions = try (0..<5).map { i in
            try makeSession(title: "s\(i)", updatedAt: now.addingTimeInterval(-Double(3600 * i)))
        }
        // Delete rows 3,4 with the current selection at row 3.
        let deletedIDs: Set<UUID> = [sessions[3].id, sessions[4].id]
        let next = PiAgentSessionGrouping.nextSelectionAfterDeletion(
            visibleSessions: sessions, deletedIDs: deletedIDs,
            selectedID: sessions[3].id)
        XCTAssertEqual(next, sessions[2].id)
    }

    /// Selected row is not in the visible list (hidden behind Show more /
    /// collapsed) but is being deleted → fall back to the first visible survivor.
    func testNextSelectionFallsBackWhenSelectedNotVisible() throws {
        let visible = try (0..<3).map { i in
            try makeSession(title: "s\(i)", updatedAt: now.addingTimeInterval(-Double(3600 * i)))
        }
        let hiddenSelected = try makeSession(title: "hidden", updatedAt: now.addingTimeInterval(-200_000))
        let next = PiAgentSessionGrouping.nextSelectionAfterDeletion(
            visibleSessions: visible, deletedIDs: [hiddenSelected.id], selectedID: hiddenSelected.id)
        XCTAssertEqual(next, visible[0].id)
    }

    /// No current selection at all → nil (don't manufacture a selection from a
    /// delete triggered while there's none).
    func testNextSelectionNilWithNoCurrentSelection() throws {
        let sessions = try (0..<3).map { i in
            try makeSession(title: "s\(i)", updatedAt: now.addingTimeInterval(-Double(3600 * i)))
        }
        let next = PiAgentSessionGrouping.nextSelectionAfterDeletion(
            visibleSessions: sessions, deletedIDs: [sessions[1].id], selectedID: nil)
        XCTAssertNil(next)
    }

    // MARK: - helpers

    private func makeSession(
        title: String,
        updatedAt: Date,
        createdAt: Date? = nil,
        status: PiAgentRunStatus = .idle,
        projectPath: String? = nil
    ) throws -> PiAgentSessionRecord {
        var session = try PiTestSupport.makeParentSession()
        session.title = title
        session.updatedAt = updatedAt
        session.createdAt = createdAt ?? updatedAt
        session.status = status
        if let projectPath {
            session.projectPath = projectPath
            session.projectName = (projectPath as NSString).lastPathComponent
        }
        return session
    }

    private func makeProject(path: String, repo: String, owner: String) throws -> DiscoveredProject {
        DiscoveredProject(
            url: URL(fileURLWithPath: path),
            gitHubRemote: GitHubRemote(
                host: "github.com",
                owner: owner,
                repo: repo,
                remoteURL: "git@github.com:\(owner)/\(repo).git"
            ),
            isGitRepository: true,
            iconFileURL: nil,
            projectType: .unknown,
            fallbackSymbolName: "folder",
            searchIndex: repo
        )
    }
}
