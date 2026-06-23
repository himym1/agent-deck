import XCTest
@testable import agent_deck

@MainActor
final class LoopExecutionStoreTests: XCTestCase {
    func testAgentPipelineLoopCompletesOnValidationSuccess() async throws {
        let store = PiAgentSessionStore(fileURL: PiTestSupport.temporaryStateFile())
        let session = try makeSession(store: store)
        var observed: [(role: String, writeTarget: LoopWriteTarget, outputPath: String?)] = []
        let draft = LoopDraft(
            goal: "Fix ticket",
            structure: .agentPipeline,
            writeTarget: .artifactMarkdown,
            validationCommand: "/usr/bin/true",
            pipeline: LoopPipelineConfig(stageNames: ["Analyze", "Implement"])
        )

        let maybeRun = await store.launchAgentPipelineLoop(session: session, draft: draft) { _, role, task, writeTarget, _, outputPath in
            observed.append((role, writeTarget, outputPath))
            return Self.fakeRun(parentSessionID: session.id, agentName: role, task: task, status: .completed, summary: "\(role) done")
        }
        let run = try XCTUnwrap(maybeRun)

        XCTAssertEqual(run.status, .completed)
        XCTAssertEqual(run.stopReason, .success)
        XCTAssertEqual(run.currentIteration, 1)
        XCTAssertEqual(run.iterations.count, 1)
        XCTAssertEqual(run.iterations[0].timeline.map(\.step), [.pipelineStage, .pipelineStage])
        XCTAssertEqual(run.iterations[0].timeline.map(\.roleName), ["Analyze", "Implement"])
        XCTAssertEqual(run.iterations[0].artifacts.first?.filename, "pipeline-summary.md")
        XCTAssertEqual(observed.map(\.role), ["Analyze", "Implement"])
        XCTAssertTrue(observed.allSatisfy { $0.writeTarget == .artifactMarkdown && $0.outputPath != nil })
    }

    func testAgentPipelineLoopStopsOnFailedStage() async throws {
        let store = PiAgentSessionStore(fileURL: PiTestSupport.temporaryStateFile())
        let session = try makeSession(store: store)
        var calls: [String] = []
        let draft = LoopDraft(
            goal: "Fix ticket",
            structure: .agentPipeline,
            writeTarget: .artifactMarkdown,
            validationCommand: "/usr/bin/true",
            pipeline: LoopPipelineConfig(stageNames: ["Analyze", "Implement"])
        )

        let maybeRun = await store.launchAgentPipelineLoop(session: session, draft: draft) { _, role, task, _, _, _ in
            calls.append(role)
            let status: PiSubagentRunStatus = role == "Implement" ? .failed : .completed
            return Self.fakeRun(parentSessionID: session.id, agentName: role, task: task, status: status, summary: "\(role) result")
        }
        let run = try XCTUnwrap(maybeRun)

        XCTAssertEqual(run.status, .failed)
        XCTAssertEqual(run.stopReason, .agentFailed)
        XCTAssertEqual(run.currentIteration, 1)
        XCTAssertEqual(run.iterations.count, 1)
        XCTAssertNil(run.iterations[0].validationResult)
        XCTAssertEqual(run.iterations[0].timeline.map(\.roleName), ["Analyze", "Implement"])
        XCTAssertEqual(calls, ["Analyze", "Implement"])
    }

    func testParallelAgentsLoopCompletesWithGraphSuccess() async throws {
        let store = PiAgentSessionStore(fileURL: PiTestSupport.temporaryStateFile())
        let session = try makeSession(store: store)
        var observedTasks: [(String, String)] = []
        var observedConcurrency = 0
        var observedUseWorktree = true
        let draft = LoopDraft(
            goal: "Compare options",
            structure: .parallelAgents,
            writeTarget: .artifactMarkdown,
            validationCommand: "/usr/bin/true",
            parallel: LoopParallelConfig(branchNames: ["BranchA", "BranchB"])
        )

        let maybeRun = await store.launchParallelAgentsLoop(session: session, draft: draft) { _, tasks, concurrency, useWorktree in
            observedTasks = tasks
            observedConcurrency = concurrency
            observedUseWorktree = useWorktree
            return Self.fakeRun(parentSessionID: session.id, agentName: "Parallel", task: "parallel", mode: .parallel, status: .completed, summary: "all done")
        }
        let run = try XCTUnwrap(maybeRun)

        XCTAssertEqual(run.status, .completed)
        XCTAssertEqual(run.stopReason, .success)
        XCTAssertEqual(run.currentIteration, 1)
        XCTAssertEqual(run.iterations.count, 1)
        XCTAssertEqual(run.iterations[0].timeline.map(\.step), [.parallelBranch, .parallelBranch])
        XCTAssertEqual(run.iterations[0].timeline.map(\.roleName), ["BranchA", "BranchB"])
        XCTAssertEqual(run.iterations[0].artifacts.first?.filename, "parallel-summary.md")
        XCTAssertEqual(observedTasks.map(\.0), ["BranchA", "BranchB"])
        XCTAssertEqual(observedConcurrency, 2)
        XCTAssertFalse(observedUseWorktree)
    }

    func testDiscoveryTriageLoopCompletesWithConfiguredAgent() async throws {
        let store = PiAgentSessionStore(fileURL: PiTestSupport.temporaryStateFile())
        let session = try makeSession(store: store)
        var observedAgent = ""
        var observedTask = ""
        let draft = LoopDraft(
            goal: "Triage failures",
            structure: .discoveryTriage,
            writeTarget: .artifactMarkdown,
            validationCommand: "/usr/bin/true",
            discoveryTriage: LoopDiscoveryTriageConfig(agentName: "Triage Agent", classificationPrompt: "severity and owner")
        )

        let maybeRun = await store.launchDiscoveryTriageLoop(session: session, draft: draft) { _, agentName, task, _, _, _ in
            observedAgent = agentName
            observedTask = task
            return Self.fakeRun(parentSessionID: session.id, agentName: agentName, task: task, status: .completed, summary: "triaged")
        }
        let run = try XCTUnwrap(maybeRun)

        XCTAssertEqual(run.status, .completed)
        XCTAssertEqual(run.stopReason, .success)
        XCTAssertEqual(run.iterations.count, 1)
        XCTAssertEqual(run.iterations[0].timeline.first?.step, .discoveryTriage)
        XCTAssertEqual(run.iterations[0].timeline.first?.roleName, "Triage Agent")
        XCTAssertEqual(run.iterations[0].artifacts.first?.filename, "discovery-triage-summary.md")
        XCTAssertEqual(observedAgent, "Triage Agent")
        XCTAssertTrue(observedTask.contains("Triage failures"))
        XCTAssertTrue(observedTask.contains("severity and owner"))
    }

    func testMakerCheckerLoopRejectThenApproveAcrossIterations() async throws {
        let store = PiAgentSessionStore(fileURL: PiTestSupport.temporaryStateFile())
        let session = try makeSession(store: store)
        var responses = ["Maker pass", "REJECT", "Maker revised", "APPROVE"]
        let draft = LoopDraft(
            goal: "Build safely",
            structure: .makerChecker,
            writeTarget: .artifactMarkdown,
            validationCommand: "/usr/bin/true",
            makerChecker: LoopMakerCheckerConfig(makerName: "Builder", checkerName: "Reviewer", checkerRubric: "approve", maxReviewRounds: 3)
        )

        let maybeRun = await store.launchMakerCheckerLoop(session: session, draft: draft) { _, role, task, _, _, _ in
            let summary = responses.removeFirst()
            return Self.fakeRun(parentSessionID: session.id, agentName: role, task: task, status: .completed, summary: summary)
        }
        let run = try XCTUnwrap(maybeRun)

        XCTAssertEqual(run.status, .completed)
        XCTAssertEqual(run.stopReason, .success)
        XCTAssertEqual(run.currentIteration, 2)
        XCTAssertEqual(run.iterations.count, 2)
        XCTAssertEqual(run.iterations.map(\.checkerResult), [.reject, .approve])
        XCTAssertEqual(run.iterations.flatMap { $0.timeline.map(\.step) }, [.makerAct, .checkerReview, .makerAct, .checkerReview])
        XCTAssertTrue(responses.isEmpty)
    }

    private func makeSession(store: PiAgentSessionStore) throws -> PiAgentSessionRecord {
        let projectURL = try PiTestSupport.temporaryProjectURL()
        return store.createSession(kind: .project, title: "Loop", project: try PiTestSupport.makeProject(url: projectURL), repository: nil)
    }

    private static func fakeRun(parentSessionID: UUID, agentName: String, task: String, mode: PiSubagentRunMode = .single, status: PiSubagentRunStatus, summary: String? = nil, error: String? = nil) -> PiSubagentRunRecord {
        let now = Date()
        return PiSubagentRunRecord(
            id: UUID(), parentSessionID: parentSessionID, mode: mode, status: status,
            agentName: agentName, task: task,
            model: nil, thinking: nil, expectedOutcome: nil, requestedOutputPath: nil, allowOverwrite: nil, readFirstPaths: nil,
            tools: [], skills: [], concurrencyLimit: nil, worktreePolicy: nil, aggregateSummary: nil,
            artifactDirectory: "", outputPath: nil, worktreePath: nil, parentRepoPath: nil, baseCommit: nil,
            isWorktreeIsolated: nil, worktreeStatus: nil, worktreePatchPath: nil,
            childSessionID: nil, childPiSessionFile: nil, launchCommand: nil,
            summary: summary, error: error, child: nil, children: nil, graphEdges: nil,
            injectedMemoryIDs: nil, injectedMemoryTitles: nil,
            createdAt: now, updatedAt: now, completedAt: status.isActive ? nil : now, durationMs: 0
        )
    }
}
