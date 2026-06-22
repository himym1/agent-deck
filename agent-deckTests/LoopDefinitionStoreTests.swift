import XCTest
@testable import agent_deck

@MainActor
final class LoopDefinitionStoreTests: XCTestCase {
    func testLoopDefinitionPersistenceRoundTripsFrontmatterAndBody() throws {
        let directory = PiTestSupport.temporaryStateFile().deletingLastPathComponent().appendingPathComponent("loops", isDirectory: true)
        let store = LoopDefinitionStore(directoryURL: directory)
        let definition = LoopDefinition(
            name: "Research Notes",
            description: "Write a markdown report",
            goalTemplate: "Research this topic and produce Markdown.",
            maxIterations: 5,
            validationCommand: "swift test",
            availability: .projectPaths,
            projectPaths: ["/tmp/project-a"]
        )

        let saved = try store.saveUserDefinition(definition)
        XCTAssertTrue(saved.filePath?.hasSuffix("research-notes.loop.md") == true)

        let loaded = try XCTUnwrap(store.loadUserDefinitions().first)
        XCTAssertEqual(loaded.name, "Research Notes")
        XCTAssertEqual(loaded.description, "Write a markdown report")
        XCTAssertEqual(loaded.goalTemplate, "Research this topic and produce Markdown.")
        XCTAssertEqual(loaded.structure, .singleAgent)
        XCTAssertEqual(loaded.writeTarget, .artifactMarkdown)
        XCTAssertEqual(loaded.maxIterations, 5)
        XCTAssertEqual(loaded.validationCommand, "swift test")
        XCTAssertEqual(loaded.source, .user)
        XCTAssertEqual(loaded.availability, .projectPaths)
        XCTAssertEqual(loaded.projectPaths, ["/tmp/project-a"])
    }

    func testProjectPathsWithFrontmatterDelimitersRoundTrip() throws {
        let directory = PiTestSupport.temporaryStateFile().deletingLastPathComponent().appendingPathComponent("loops", isDirectory: true)
        let store = LoopDefinitionStore(directoryURL: directory)
        let pathWithDelimiter = "/tmp/project|with-delimiter"

        _ = try store.saveUserDefinition(LoopDefinition(
            name: "Delimited Project",
            goalTemplate: "Goal",
            availability: .projectPaths,
            projectPaths: [pathWithDelimiter]
        ))

        let loaded = try XCTUnwrap(store.loadUserDefinitions().first)
        XCTAssertEqual(loaded.projectPaths, [pathWithDelimiter])
        XCTAssertTrue(loaded.isAvailable(in: pathWithDelimiter))
    }

    func testSlugCollisionsCreateDistinctDefinitionFiles() throws {
        let directory = PiTestSupport.temporaryStateFile().deletingLastPathComponent().appendingPathComponent("loops", isDirectory: true)
        let store = LoopDefinitionStore(directoryURL: directory)

        let first = try store.saveUserDefinition(LoopDefinition(name: "A/B", goalTemplate: "First"))
        let second = try store.saveUserDefinition(LoopDefinition(name: "A B", goalTemplate: "Second"))

        XCTAssertNotEqual(first.filePath, second.filePath)
        XCTAssertEqual(store.loadUserDefinitions().map(\.goalTemplate).sorted(), ["First", "Second"])
    }

    func testAppViewModelSlashUniverseIncludesCreateThenAvailableSavedLoops() throws {
        let directory = PiTestSupport.temporaryStateFile().deletingLastPathComponent().appendingPathComponent("loops", isDirectory: true)
        let store = LoopDefinitionStore(directoryURL: directory)
        _ = try store.saveUserDefinition(LoopDefinition(
            name: "Global Loop",
            description: "Everywhere",
            goalTemplate: "Global goal"
        ))
        _ = try store.saveUserDefinition(LoopDefinition(
            name: "Project Loop",
            description: "Only here",
            goalTemplate: "Project goal",
            availability: .projectPaths,
            projectPaths: ["/tmp/project-a"]
        ))
        _ = try store.saveUserDefinition(LoopDefinition(
            name: "Other Project Loop",
            goalTemplate: "Other goal",
            availability: .projectPaths,
            projectPaths: ["/tmp/project-b"]
        ))

        let viewModel = AppViewModel()
        viewModel.configureLoopDefinitionStoreForTesting(directoryURL: directory)
        let universe = viewModel.slashUniverse(forProjectPath: "/tmp/project-a")

        XCTAssertEqual(universe.loops.map(\.displayName), ["Create New Loop…", "Global Loop", "Project Loop"])
        XCTAssertTrue(universe.loops.dropFirst().allSatisfy { item in
            if case .loopDefinition = item.payload { return true }
            return false
        })
    }

    func testSavedLoopConvertsToFreshLaunchDraft() {
        let definition = LoopDefinition(
            name: "Reusable",
            goalTemplate: "Use this saved goal",
            maxIterations: 7,
            validationCommand: "swift test"
        )

        let draft = definition.makeDraft()
        XCTAssertEqual(draft.goal, "Use this saved goal")
        XCTAssertEqual(draft.structure, .singleAgent)
        XCTAssertEqual(draft.writeTarget, .artifactMarkdown)
        XCTAssertEqual(draft.maxIterations, 7)
        XCTAssertEqual(draft.validationCommand, "swift test")
    }
}
