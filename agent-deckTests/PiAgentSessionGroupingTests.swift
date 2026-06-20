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

    func testWorkingAndPinnedDoNotOverrideRecencyRule() throws {
        let oldWorking = try makeSession(title: "working", updatedAt: now.addingTimeInterval(-100_000), status: .running)
        let oldPinned = try makeSession(title: "pinned", updatedAt: now.addingTimeInterval(-100_001), isPinned: true)
        let newer = try (0..<5).map { i in
            try makeSession(title: "newer\(i)", updatedAt: now.addingTimeInterval(-Double(30_000 + i)))
        }
        let split = PiAgentSessionGrouping.previewSplit(
            sessions: [oldWorking, oldPinned] + newer, isExpanded: false, capPreviews: true,
            isWorking: { $0.status == .running }, selectedSessionID: nil, now: now, options: .default)
        XCTAssertFalse(split.preview.contains { $0.title == "working" })
        XCTAssertFalse(split.preview.contains { $0.title == "pinned" })
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

    // MARK: - helpers

    private func makeSession(
        title: String,
        updatedAt: Date,
        createdAt: Date? = nil,
        status: PiAgentRunStatus = .idle,
        isPinned: Bool = false,
        projectPath: String? = nil
    ) throws -> PiAgentSessionRecord {
        var session = try PiTestSupport.makeParentSession()
        session.title = title
        session.updatedAt = updatedAt
        session.createdAt = createdAt ?? updatedAt
        session.status = status
        session.isPinned = isPinned
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
