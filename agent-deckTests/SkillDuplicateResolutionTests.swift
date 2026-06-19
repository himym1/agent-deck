import XCTest
@testable import agent_deck

/// Tests for the source-aware duplicate-skill resolution helper.
///
/// The key invariant: resolving a duplicate removes the losing *copy* while
/// leaving name-based assignments alone. `SkillDuplicateResolution` itself
/// has no assignment-clearing hook; the AppViewModel wrapper guarantees the
/// caller never invokes `removeSkillReferences(named:)`.
@MainActor
final class SkillDuplicateResolutionTests: XCTestCase {

    // MARK: - Helpers

    private func makeSkill(
        name: String,
        path: String,
        sourceKind: ResourceScopeKind
    ) -> SkillRecord {
        SkillRecord(
            id: "\(sourceKind.rawValue):\(name):\(path)",
            name: name,
            description: nil,
            source: ScopeID(kind: sourceKind, path: path),
            filePath: path,
            body: ""
        )
    }

    // MARK: - Local skill duplicate

    func testRemoveLocalDuplicateMovesLoserToTrash() throws {
        let kept = makeSkill(name: "swiftui-liquid-glass", path: "/Users/me/.pi/agent/skills/swiftui-liquid-glass/SKILL.md", sourceKind: .global)
        let loser = makeSkill(name: "swiftui-liquid-glass", path: "/Users/me/project/.pi/skills/swiftui-liquid-glass/SKILL.md", sourceKind: .project)

        var deleted: [SkillRecord] = []
        var unlisted: [SkillRecord] = []
        var externalPathsRemoved: [SkillRecord] = []

        try SkillDuplicateResolution.removeDuplicateCopies(
            keeping: kept,
            removing: [loser],
            canDelete: { _ in true },
            delete: { deleted.append($0) },
            isImported: { _ in false },
            removeExternalPath: { externalPathsRemoved.append($0) },
            unlistFromSyncedRepository: { unlisted.append($0) }
        )

        XCTAssertEqual(deleted, [loser])
        XCTAssertTrue(unlisted.isEmpty)
        XCTAssertTrue(externalPathsRemoved.isEmpty)
    }

    func testRemoveLocalDuplicateRefusesUndeletableSkill() {
        let kept = makeSkill(name: "swiftui-liquid-glass", path: "/Users/me/.pi/agent/skills/swiftui-liquid-glass/SKILL.md", sourceKind: .global)
        let loser = makeSkill(name: "swiftui-liquid-glass", path: "/Users/me/project/.pi/skills/swiftui-liquid-glass/SKILL.md", sourceKind: .project)

        XCTAssertThrowsError(
            try SkillDuplicateResolution.removeDuplicateCopies(
                keeping: kept,
                removing: [loser],
                canDelete: { _ in false },
                delete: { _ in },
                isImported: { _ in false },
                removeExternalPath: { _ in },
                unlistFromSyncedRepository: { _ in }
            )
        ) { error in
            guard case SkillDuplicateResolution.Error.cannotDeleteSkill(let failed) = error else {
                return XCTFail("Expected cannotDeleteSkill, got \(error)")
            }
            XCTAssertEqual(failed.id, loser.id)
        }
    }

    // MARK: - Imported / synced skill duplicate

    func testRemoveImportedDuplicateUnlistsAndDropsExternalPath() throws {
        let kept = makeSkill(name: "swiftui-liquid-glass", path: "/Users/me/.pi/agent/skills/swiftui-liquid-glass/SKILL.md", sourceKind: .global)
        let loser = makeSkill(name: "swiftui-liquid-glass", path: "/Users/me/Library/Application Support/agent-deck/skill-repos/openai-plugins/skills/swiftui-liquid-glass/SKILL.md", sourceKind: .library)

        var deleted: [SkillRecord] = []
        var unlisted: [SkillRecord] = []
        var externalPathsRemoved: [SkillRecord] = []

        try SkillDuplicateResolution.removeDuplicateCopies(
            keeping: kept,
            removing: [loser],
            canDelete: { _ in true },
            delete: { deleted.append($0) },
            isImported: { _ in true },
            removeExternalPath: { externalPathsRemoved.append($0) },
            unlistFromSyncedRepository: { unlisted.append($0) }
        )

        XCTAssertTrue(deleted.isEmpty, "Imported duplicates must not be trashed")
        XCTAssertEqual(unlisted, [loser])
        XCTAssertEqual(externalPathsRemoved, [loser])
    }

    func testRemoveSyncedRepoDuplicateDoesNotTrashFiles() throws {
        let kept = makeSkill(name: "swiftui-view-refactor", path: "/Users/me/.pi/agent/skills/swiftui-view-refactor/SKILL.md", sourceKind: .global)
        let loser = makeSkill(name: "swiftui-view-refactor", path: "/Users/me/Library/Application Support/agent-deck/skill-repos/steipete-agent-scripts/skills/swiftui-view-refactor/SKILL.md", sourceKind: .library)

        var deleted: [SkillRecord] = []

        try SkillDuplicateResolution.removeDuplicateCopies(
            keeping: kept,
            removing: [loser],
            canDelete: { _ in true },
            delete: { deleted.append($0) },
            isImported: { _ in true },
            removeExternalPath: { _ in },
            unlistFromSyncedRepository: { _ in }
        )

        XCTAssertTrue(deleted.isEmpty)
    }

    // MARK: - Multi-way duplicates

    func testRemoveMultipleLocalCopiesKeepsOnlyWinner() throws {
        let kept = makeSkill(name: "swiftui-liquid-glass", path: "/Users/me/.pi/agent/skills/swiftui-liquid-glass/SKILL.md", sourceKind: .global)
        let loserA = makeSkill(name: "swiftui-liquid-glass", path: "/Users/me/project-a/.pi/skills/swiftui-liquid-glass/SKILL.md", sourceKind: .project)
        let loserB = makeSkill(name: "swiftui-liquid-glass", path: "/Users/me/project-b/.pi/skills/swiftui-liquid-glass/SKILL.md", sourceKind: .project)

        var deleted: Set<String> = []

        try SkillDuplicateResolution.removeDuplicateCopies(
            keeping: kept,
            removing: [loserA, loserB],
            canDelete: { _ in true },
            delete: { deleted.insert($0.id) },
            isImported: { _ in false },
            removeExternalPath: { _ in },
            unlistFromSyncedRepository: { _ in }
        )

        XCTAssertEqual(deleted, Set([loserA.id, loserB.id]))
    }

    // MARK: - Protected sources

    func testCannotResolveByRemovingBundledCopy() {
        let bundled = makeSkill(name: "swiftui-liquid-glass", path: "/Applications/Agent Deck.app/.../swiftui-liquid-glass/SKILL.md", sourceKind: .builtin)
        let userCopy = makeSkill(name: "swiftui-liquid-glass", path: "/Users/me/.pi/agent/skills/swiftui-liquid-glass/SKILL.md", sourceKind: .global)

        XCTAssertThrowsError(
            try SkillDuplicateResolution.removeDuplicateCopies(
                keeping: userCopy,
                removing: [bundled],
                canDelete: { _ in false },
                delete: { _ in },
                isImported: { _ in false },
                removeExternalPath: { _ in },
                unlistFromSyncedRepository: { _ in }
            )
        ) { error in
            guard case SkillDuplicateResolution.Error.cannotRemoveBundledOrPackageSkill(let failed) = error else {
                return XCTFail("Expected cannotRemoveBundledOrPackageSkill, got \(error)")
            }
            XCTAssertEqual(failed.id, bundled.id)
        }
    }

    func testCannotResolveByRemovingPackageCopy() {
        let package = makeSkill(name: "swiftui-liquid-glass", path: "/Users/me/project/.build/.../swiftui-liquid-glass/SKILL.md", sourceKind: .package)
        let userCopy = makeSkill(name: "swiftui-liquid-glass", path: "/Users/me/.pi/agent/skills/swiftui-liquid-glass/SKILL.md", sourceKind: .global)

        XCTAssertThrowsError(
            try SkillDuplicateResolution.removeDuplicateCopies(
                keeping: userCopy,
                removing: [package],
                canDelete: { _ in false },
                delete: { _ in },
                isImported: { _ in false },
                removeExternalPath: { _ in },
                unlistFromSyncedRepository: { _ in }
            )
        ) { error in
            guard case SkillDuplicateResolution.Error.cannotRemoveBundledOrPackageSkill = error else {
                return XCTFail("Expected cannotRemoveBundledOrPackageSkill, got \(error)")
            }
        }
    }

    // MARK: - Preflight / atomicity

    func testPreflightPreventsPartialResolution() {
        let kept = makeSkill(name: "swiftui-liquid-glass", path: "/Users/me/.pi/agent/skills/swiftui-liquid-glass/SKILL.md", sourceKind: .global)
        let deletableLoser = makeSkill(name: "swiftui-liquid-glass", path: "/Users/me/project-a/.pi/skills/swiftui-liquid-glass/SKILL.md", sourceKind: .project)
        let bundledLoser = makeSkill(name: "swiftui-liquid-glass", path: "/Applications/Agent Deck.app/.../swiftui-liquid-glass/SKILL.md", sourceKind: .builtin)

        var deleted: [SkillRecord] = []

        XCTAssertThrowsError(
            try SkillDuplicateResolution.removeDuplicateCopies(
                keeping: kept,
                removing: [deletableLoser, bundledLoser],
                canDelete: { _ in true },
                delete: { deleted.append($0) },
                isImported: { _ in false },
                removeExternalPath: { _ in },
                unlistFromSyncedRepository: { _ in }
            )
        ) { error in
            guard case SkillDuplicateResolution.Error.cannotRemoveBundledOrPackageSkill = error else {
                return XCTFail("Expected cannotRemoveBundledOrPackageSkill, got \(error)")
            }
        }

        XCTAssertTrue(deleted.isEmpty, "No deletion should happen when preflight fails")
    }

    func testCanResolveRejectsBundledLoser() {
        let kept = makeSkill(name: "swiftui-liquid-glass", path: "/Users/me/.pi/agent/skills/swiftui-liquid-glass/SKILL.md", sourceKind: .global)
        let bundled = makeSkill(name: "swiftui-liquid-glass", path: "/Applications/Agent Deck.app/.../swiftui-liquid-glass/SKILL.md", sourceKind: .builtin)

        XCTAssertFalse(SkillDuplicateResolution.canResolve(
            keeping: kept,
            removing: [bundled],
            canDelete: { _ in true },
            isImported: { _ in false }
        ))
    }

    func testCanResolveRejectsUndeletableLocalLoser() {
        let kept = makeSkill(name: "swiftui-liquid-glass", path: "/Users/me/.pi/agent/skills/swiftui-liquid-glass/SKILL.md", sourceKind: .global)
        let loser = makeSkill(name: "swiftui-liquid-glass", path: "/Users/me/project/.pi/skills/swiftui-liquid-glass/SKILL.md", sourceKind: .project)

        XCTAssertFalse(SkillDuplicateResolution.canResolve(
            keeping: kept,
            removing: [loser],
            canDelete: { _ in false },
            isImported: { _ in false }
        ))
    }

    func testCanResolveAcceptsImportedLoser() {
        let kept = makeSkill(name: "swiftui-liquid-glass", path: "/Users/me/.pi/agent/skills/swiftui-liquid-glass/SKILL.md", sourceKind: .global)
        let loser = makeSkill(name: "swiftui-liquid-glass", path: "/Users/me/lib/skills/swiftui-liquid-glass/SKILL.md", sourceKind: .library)

        XCTAssertTrue(SkillDuplicateResolution.canResolve(
            keeping: kept,
            removing: [loser],
            canDelete: { _ in false },
            isImported: { _ in true }
        ))
    }

    func testCanResolveAcceptsDeletableLocalLoser() {
        let kept = makeSkill(name: "swiftui-liquid-glass", path: "/Users/me/.pi/agent/skills/swiftui-liquid-glass/SKILL.md", sourceKind: .global)
        let loser = makeSkill(name: "swiftui-liquid-glass", path: "/Users/me/project/.pi/skills/swiftui-liquid-glass/SKILL.md", sourceKind: .project)

        XCTAssertTrue(SkillDuplicateResolution.canResolve(
            keeping: kept,
            removing: [loser],
            canDelete: { _ in true },
            isImported: { _ in false }
        ))
    }

    // MARK: - Validation

    func testMismatchedSkillNamesThrow() {
        let kept = makeSkill(name: "swiftui-liquid-glass", path: "/Users/me/.pi/agent/skills/swiftui-liquid-glass/SKILL.md", sourceKind: .global)
        let loser = makeSkill(name: "swiftui-view-refactor", path: "/Users/me/project/.pi/skills/swiftui-view-refactor/SKILL.md", sourceKind: .project)

        XCTAssertThrowsError(
            try SkillDuplicateResolution.removeDuplicateCopies(
                keeping: kept,
                removing: [loser],
                canDelete: { _ in true },
                delete: { _ in },
                isImported: { _ in false },
                removeExternalPath: { _ in },
                unlistFromSyncedRepository: { _ in }
            )
        ) { error in
            guard case SkillDuplicateResolution.Error.mismatchedSkillNames = error else {
                return XCTFail("Expected mismatchedSkillNames, got \(error)")
            }
        }
    }

    func testKeptSkillCannotAppearInRemovedSkills() {
        let kept = makeSkill(name: "swiftui-liquid-glass", path: "/Users/me/.pi/agent/skills/swiftui-liquid-glass/SKILL.md", sourceKind: .global)

        XCTAssertThrowsError(
            try SkillDuplicateResolution.removeDuplicateCopies(
                keeping: kept,
                removing: [kept],
                canDelete: { _ in true },
                delete: { _ in },
                isImported: { _ in false },
                removeExternalPath: { _ in },
                unlistFromSyncedRepository: { _ in }
            )
        ) { error in
            guard case SkillDuplicateResolution.Error.mismatchedSkillNames = error else {
                return XCTFail("Expected mismatchedSkillNames, got \(error)")
            }
        }
    }

    // MARK: - Summary descriptions

    func testSummaryDescribesLocalRemoval() throws {
        let kept = makeSkill(name: "swiftui-liquid-glass", path: "/Users/me/.pi/agent/skills/swiftui-liquid-glass/SKILL.md", sourceKind: .global)
        let loser = makeSkill(name: "swiftui-liquid-glass", path: "/Users/me/project/.pi/skills/swiftui-liquid-glass/SKILL.md", sourceKind: .project)

        let summary = try SkillDuplicateResolution.summary(
            keeping: kept,
            removing: [loser],
            isImported: { _ in false }
        )

        XCTAssertEqual(summary.keptSkill.id, kept.id)
        XCTAssertEqual(summary.removedSkills, [loser])
        XCTAssertEqual(summary.descriptions.count, 1)
        XCTAssertTrue(summary.descriptions[0].contains("local copy"))
        XCTAssertTrue(summary.descriptions[0].contains(loser.filePath))
    }

    func testSummaryDescribesImportedRemoval() throws {
        let kept = makeSkill(name: "swiftui-liquid-glass", path: "/Users/me/.pi/agent/skills/swiftui-liquid-glass/SKILL.md", sourceKind: .global)
        let loser = makeSkill(name: "swiftui-liquid-glass", path: "/Users/me/Library/Application Support/agent-deck/skill-repos/openai-plugins/skills/swiftui-liquid-glass/SKILL.md", sourceKind: .library)

        let summary = try SkillDuplicateResolution.summary(
            keeping: kept,
            removing: [loser],
            isImported: { _ in true }
        )

        XCTAssertTrue(summary.descriptions[0].contains("imported/synced copy"))
    }
}
