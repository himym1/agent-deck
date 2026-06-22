import XCTest
@testable import agent_deck

@MainActor
final class LoopSkeletonTests: XCTestCase {
    func testSlashUniverseIncludesLoopsCategoryAndCreateNewLoop() {
        let item = SlashItem(
            id: "loop:create-new",
            kind: .loop,
            displayName: "Create New Loop…",
            description: nil,
            scopeLabel: "Unsaved",
            isActive: true,
            payload: .loopCreateNew
        )
        let universe = SlashUniverse(skills: [], prompts: [], commands: [], loops: [item])

        let categories = SlashSuggestionRowBuilder.rows(universe: universe, state: .init(), query: "")
        XCTAssertTrue(categories.contains { row in
            if case .category(.loop) = row.kind { return true }
            return false
        })

        let loopRows = SlashSuggestionRowBuilder.rows(
            universe: universe,
            state: SlashSuggestionState(screen: .category(.loop)),
            query: ""
        )
        XCTAssertEqual(loopRows.compactMap { row -> String? in
            if case .item(let item) = row.kind { return item.displayName }
            return nil
        }, ["Create New Loop…"])
        XCTAssertEqual(item.materialize(userText: "do not send"), "do not send")
    }

    func testSmokeLoopLaunchCompletesAndWritesFileBackedTranscriptCard() throws {
        let stateFile = PiTestSupport.temporaryStateFile()
        let projectURL = try PiTestSupport.temporaryProjectURL()
        let store = PiAgentSessionStore(fileURL: stateFile)
        let session = store.createSession(kind: .project, title: "Loop", project: try PiTestSupport.makeProject(url: projectURL), repository: nil)

        let run = try XCTUnwrap(store.launchSmokeLoop(
            sessionID: session.id,
            projectPath: session.projectPath,
            draft: LoopDraft(goal: "Produce a markdown smoke artifact", validationCommand: "/usr/bin/true")
        ))
        let artifact = try XCTUnwrap(run.iterations.first?.artifacts.first)
        let artifactPath = try XCTUnwrap(artifact.filePath)
        let artifactDirectoryPath = try XCTUnwrap(run.artifactDirectoryPath)

        XCTAssertEqual(run.status, .completed)
        XCTAssertEqual(run.stopReason, .success)
        XCTAssertEqual(run.currentIteration, 1)
        XCTAssertEqual(artifact.filename, "loop-smoke.md")
        XCTAssertEqual(run.iterations.first?.validationResult?.exitCode, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifactPath))
        XCTAssertEqual(try String(contentsOfFile: artifactPath, encoding: .utf8), artifact.markdown)
        XCTAssertTrue(path(artifactPath, isUnder: stateFile.deletingLastPathComponent().path))
        XCTAssertTrue(path(artifactDirectoryPath, isUnder: stateFile.deletingLastPathComponent().path))
        XCTAssertFalse(path(artifactPath, isUnder: projectURL.path))
        XCTAssertNil(store.activeLoopRun(for: session.id))

        let loopEntries = store.transcript(for: session.id).filter { $0.title == LoopRunTranscriptCodec.title }
        XCTAssertEqual(loopEntries.count, 1)
        XCTAssertTrue(loopEntries[0].text.contains("Stop reason: Success"))
        XCTAssertTrue(loopEntries[0].text.contains("Artifact directory: \(artifactDirectoryPath)"))
        XCTAssertTrue(loopEntries[0].text.contains("Artifact path: \(artifactPath)"))
        XCTAssertTrue(loopEntries[0].text.contains("# Loop Smoke Output"))
        XCTAssertEqual(LoopRunTranscriptCodec.decode(from: loopEntries[0])?.id, run.id)
        XCTAssertTrue(loopEntries[0].isLoopTranscriptCard)
    }

    func testHydratingTranscriptWithoutLoopEntriesClearsCachedLoopRuns() throws {
        let store = PiAgentSessionStore(fileURL: PiTestSupport.temporaryStateFile())
        let session = store.createSession(kind: .project, title: "Loop", project: try PiTestSupport.makeProject(), repository: nil)
        _ = try XCTUnwrap(store.launchSmokeLoop(
            sessionID: session.id,
            projectPath: session.projectPath,
            draft: LoopDraft(goal: "Temporary loop", validationCommand: "/usr/bin/true")
        ))
        XCTAssertFalse(store.loopRuns(for: session.id).isEmpty)

        store.updateEntry(store.transcript(for: session.id)[0].id, in: session.id) { entry in
            entry.title = "Other Status"
            entry.rawJSON = nil
        }
        store.hydrateLoopRunsFromTranscript(sessionID: session.id)

        XCTAssertTrue(store.loopRuns(for: session.id).isEmpty)
    }

    func testLoopRunsHydrateFromPersistedTranscript() async throws {
        let fileURL = PiTestSupport.temporaryStateFile()
        let firstStore = PiAgentSessionStore(fileURL: fileURL)
        firstStore.configureTranscriptMemory(lazyLoadingEnabled: false, cacheLimit: 10)
        let session = firstStore.createSession(kind: .project, title: "Loop", project: try PiTestSupport.makeProject(), repository: nil)
        let run = try XCTUnwrap(firstStore.launchSmokeLoop(
            sessionID: session.id,
            projectPath: session.projectPath,
            draft: LoopDraft(goal: "Persist this loop card", validationCommand: "/usr/bin/true")
        ))
        firstStore.flushForTesting()

        let reloadedStore = PiAgentSessionStore(fileURL: fileURL)
        await reloadedStore.waitForLoadForTesting()
        reloadedStore.configureTranscriptMemory(lazyLoadingEnabled: false, cacheLimit: 10)

        let hydratedRun = try XCTUnwrap(reloadedStore.loopRuns(for: session.id).first)
        let hydratedArtifact = try XCTUnwrap(hydratedRun.iterations.first?.artifacts.first)
        XCTAssertEqual(hydratedRun.id, run.id)
        XCTAssertEqual(hydratedRun.stopReason, .success)
        XCTAssertEqual(hydratedRun.artifactDirectoryPath, run.artifactDirectoryPath)
        XCTAssertEqual(hydratedArtifact.filePath, run.iterations.first?.artifacts.first?.filePath)
        XCTAssertEqual(hydratedRun.iterations.first?.validationResult?.exitCode, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(hydratedArtifact.filePath)))
    }

    func testLegacyLoopRunJSONWithoutValidationCommandStillDecodes() throws {
        let sessionID = UUID()
        let run = LoopRun(
            sessionID: sessionID,
            projectPath: nil,
            draft: LoopDraft(goal: "Legacy", validationCommand: "/usr/bin/true")
        )
        let rawJSON = try XCTUnwrap(LoopRunTranscriptCodec.rawJSON(for: run))
        let data = try XCTUnwrap(rawJSON.data(using: .utf8))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "validationCommand")
        let legacyData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let legacyRawJSON = try XCTUnwrap(String(data: legacyData, encoding: .utf8))
        let entry = PiAgentTranscriptEntry(
            sessionID: sessionID,
            role: .status,
            title: LoopRunTranscriptCodec.title,
            text: "Loop",
            rawJSON: legacyRawJSON
        )

        let decoded = try XCTUnwrap(LoopRunTranscriptCodec.decode(from: entry))
        XCTAssertEqual(decoded.id, run.id)
        XCTAssertEqual(decoded.validationCommand, "")
    }

    func testPassingValidationCommandStopsFirstIteration() throws {
        let stateFile = PiTestSupport.temporaryStateFile()
        let projectURL = try PiTestSupport.temporaryProjectURL()
        let store = PiAgentSessionStore(fileURL: stateFile)
        let session = store.createSession(kind: .project, title: "Loop", project: try PiTestSupport.makeProject(url: projectURL), repository: nil)

        let run = try XCTUnwrap(store.launchSmokeLoop(
            sessionID: session.id,
            projectPath: session.projectPath,
            draft: LoopDraft(goal: "Validate once", maxIterations: 3, validationCommand: "/usr/bin/true")
        ))

        XCTAssertEqual(run.status, .completed)
        XCTAssertEqual(run.stopReason, .success)
        XCTAssertEqual(run.currentIteration, 1)
        XCTAssertEqual(run.iterations.count, 1)
        XCTAssertEqual(run.iterations[0].validationResult?.exitCode, 0)
    }

    func testFailingValidationRepeatsToMaxIterationsAndRecordsFinalStopReason() throws {
        let stateFile = PiTestSupport.temporaryStateFile()
        let projectURL = try PiTestSupport.temporaryProjectURL()
        let store = PiAgentSessionStore(fileURL: stateFile)
        let session = store.createSession(kind: .project, title: "Loop", project: try PiTestSupport.makeProject(url: projectURL), repository: nil)

        let run = try XCTUnwrap(store.launchSmokeLoop(
            sessionID: session.id,
            projectPath: session.projectPath,
            draft: LoopDraft(goal: "Retry validation", maxIterations: 3, validationCommand: "/usr/bin/false")
        ))

        XCTAssertEqual(run.status, .failed)
        XCTAssertEqual(run.stopReason, .validationFailedAfterFinalIteration)
        XCTAssertEqual(run.currentIteration, 3)
        XCTAssertEqual(run.iterations.count, 3)
        XCTAssertEqual(run.iterations.map { $0.validationResult?.exitCode }, [1, 1, 1])
        XCTAssertEqual(run.iterations.map { $0.artifacts.first?.filename }, ["loop-smoke.md", "loop-smoke-2.md", "loop-smoke-3.md"])
    }

    func testMissingValidationCommandRecordsValidationUnavailable() throws {
        let stateFile = PiTestSupport.temporaryStateFile()
        let projectURL = try PiTestSupport.temporaryProjectURL()
        let store = PiAgentSessionStore(fileURL: stateFile)
        let session = store.createSession(kind: .project, title: "Loop", project: try PiTestSupport.makeProject(url: projectURL), repository: nil)

        let run = try XCTUnwrap(store.launchSmokeLoop(
            sessionID: session.id,
            projectPath: session.projectPath,
            draft: LoopDraft(goal: "No validation", maxIterations: 3)
        ))

        XCTAssertEqual(run.status, .failed)
        XCTAssertEqual(run.stopReason, .validationUnavailable)
        XCTAssertEqual(run.currentIteration, 1)
        XCTAssertEqual(run.iterations.count, 1)
        XCTAssertNil(run.iterations[0].validationResult?.exitCode)
        XCTAssertEqual(run.iterations[0].validationResult?.stderr, "Validation command is empty.")
    }

    private func path(_ path: String, isUnder parentPath: String) -> Bool {
        let child = URL(fileURLWithPath: path).standardizedFileURL.path
        let parent = URL(fileURLWithPath: parentPath).standardizedFileURL.path
        return child == parent || child.hasPrefix(parent + "/")
    }

    func testActiveLoopBlocksSecondLaunchUnlessStopFirst() throws {
        let store = PiAgentSessionStore(fileURL: PiTestSupport.temporaryStateFile())
        let session = store.createSession(kind: .project, title: "Loop", project: try PiTestSupport.makeProject(), repository: nil)
        let active = LoopRun(sessionID: session.id, projectPath: session.projectPath, draft: LoopDraft(goal: "Active"))
        store.upsert(.init(
            id: active.transcriptEntryID,
            sessionID: session.id,
            role: .status,
            title: LoopRunTranscriptCodec.title,
            text: LoopRunTranscriptCodec.transcriptText(for: active),
            rawJSON: LoopRunTranscriptCodec.rawJSON(for: active)
        ))
        store.hydrateLoopRunsFromTranscript(sessionID: session.id)

        XCTAssertNil(store.launchSmokeLoop(sessionID: session.id, projectPath: session.projectPath, draft: LoopDraft(goal: "Second")))
        XCTAssertNotNil(store.activeLoopRun(for: session.id))

        let second = try XCTUnwrap(store.launchSmokeLoop(sessionID: session.id, projectPath: session.projectPath, draft: LoopDraft(goal: "Second", validationCommand: "/usr/bin/true"), stopExistingActive: true))
        XCTAssertEqual(second.status, .completed)
        XCTAssertNil(store.activeLoopRun(for: session.id))
        XCTAssertTrue(store.loopRuns(for: session.id).contains { $0.id == active.id && $0.stopReason == .userStopped })
    }
}
