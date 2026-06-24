import XCTest
@testable import agent_deck

@MainActor
final class LoopExecutionStoreTests: XCTestCase {
    func testSingleAgentLoopCompletesOnValidationSuccess() async throws {
        let store = PiAgentSessionStore(fileURL: PiTestSupport.temporaryStateFile())
        let session = try makeSession(store: store)
        var observedAgent = ""
        var observedWriteTarget: LoopWriteTarget?
        var observedOutputPath: String?
        var observedTask = ""
        let draft = LoopDraft(
            goal: "Produce report",
            structure: .singleAgent,
            writeTarget: .artifactMarkdown,
            validationCommand: "/usr/bin/true",
            makerChecker: LoopMakerCheckerConfig(makerName: "Explorer")
        )

        let maybeRun = await store.launchSingleAgentLoop(session: session, draft: draft) { _, agentName, task, writeTarget, _, outputPath in
            observedAgent = agentName
            observedWriteTarget = writeTarget
            observedOutputPath = outputPath
            observedTask = task
            return Self.fakeRun(parentSessionID: session.id, agentName: agentName, task: task, status: .completed, summary: "done")
        }
        let run = try XCTUnwrap(maybeRun)

        XCTAssertEqual(run.status, .completed)
        XCTAssertEqual(run.stopReason, .success)
        XCTAssertEqual(run.currentIteration, 1)
        XCTAssertEqual(run.iterations.count, 1)
        XCTAssertEqual(run.iterations[0].timeline.map(\.step), [.makerAct])
        XCTAssertEqual(run.iterations[0].timeline.map(\.roleName), ["Explorer"])
        XCTAssertEqual(run.iterations[0].artifacts.first?.filename, "single-agent-summary.md")
        XCTAssertEqual(observedAgent, "Explorer")
        XCTAssertEqual(observedWriteTarget, .artifactMarkdown)
        XCTAssertNotNil(observedOutputPath)
        XCTAssertTrue(observedTask.contains("Agent Deck controls iteration count, retries, stopping, artifacts, and validation"))
        XCTAssertTrue(observedTask.contains("Do not run your own open-ended loop"))
        XCTAssertTrue(observedTask.contains("You are completing one implementation/review pass"))
    }

    func testLaunchContextInjectionRespectsScope() async throws {
        let store = PiAgentSessionStore(fileURL: PiTestSupport.temporaryStateFile())
        let session = try makeSession(store: store)
        var tasks: [String] = []
        let draft = LoopDraft(
            goal: "Use context",
            launchContext: "Secret launch notes\nSecond line",
            launchContextScope: .firstIterationOnly,
            structure: .singleAgent,
            maxIterations: 2,
            validationCommand: "/usr/bin/false",
            makerChecker: LoopMakerCheckerConfig(makerName: "Explorer")
        )

        _ = await store.launchSingleAgentLoop(session: session, draft: draft) { _, agentName, task, _, _, _ in
            tasks.append(task)
            return Self.fakeRun(parentSessionID: session.id, agentName: agentName, task: task, status: .completed, summary: "done")
        }

        XCTAssertEqual(tasks.count, 2)
        XCTAssertTrue(tasks[0].contains("Launch context (first iteration only):\nSecret launch notes\nSecond line"))
        XCTAssertFalse(tasks[1].contains("Secret launch notes"))
    }

    func testLoopSeparatorsAndFinalRecapAreGeneratedAndDeduplicated() async throws {
        let store = PiAgentSessionStore(fileURL: PiTestSupport.temporaryStateFile())
        let session = try makeSession(store: store)
        let draft = LoopDraft(
            goal: "Recap this",
            structure: .singleAgent,
            writeTarget: .artifactMarkdown,
            validationCommand: "/usr/bin/true",
            makerChecker: LoopMakerCheckerConfig(makerName: "Explorer")
        )

        let maybeRun = await store.launchSingleAgentLoop(session: session, draft: draft) { _, agentName, task, _, _, _ in
            Self.fakeRun(parentSessionID: session.id, agentName: agentName, task: task, status: .completed, summary: "done")
        }
        let run = try XCTUnwrap(maybeRun)

        let transcript = store.transcriptsBySessionID[session.id] ?? []
        let separators = transcript.compactMap { entry -> (PiAgentTranscriptEntry, LoopRunRecapMarker)? in
            guard let marker = LoopIterationSeparatorCodec.decode(from: entry) else { return nil }
            return (entry, marker)
        }
        let recaps = transcript.compactMap { entry -> (PiAgentTranscriptEntry, LoopRunRecapMarker)? in
            guard let marker = LoopRunRecapCodec.decode(from: entry) else { return nil }
            return (entry, marker)
        }
        XCTAssertEqual(separators.count, 1)
        XCTAssertEqual(separators.first?.1.kind, .iteration)
        XCTAssertTrue(separators.first?.0.text.contains("Iteration 1 of") == true)
        XCTAssertEqual(recaps.count, 1)
        XCTAssertEqual(recaps.first?.1.kind, .final)
        XCTAssertTrue(recaps.contains { $0.0.text.contains("Loop final recap") && $0.0.text.contains("Stop reason: Success") })

        store.hydrateLoopRunsFromTranscript(sessionID: session.id)
        let afterHydrateRecaps = (store.transcriptsBySessionID[session.id] ?? []).compactMap(LoopRunRecapCodec.decode(from:))
        let afterHydrateSeparators = (store.transcriptsBySessionID[session.id] ?? []).compactMap(LoopIterationSeparatorCodec.decode(from:))
        XCTAssertEqual(afterHydrateRecaps.count, 1)
        XCTAssertEqual(afterHydrateRecaps.filter { $0.runID == run.id && $0.kind == .final }.count, 1)
        XCTAssertEqual(afterHydrateSeparators.filter { $0.runID == run.id && $0.kind == .iteration }.count, 1)
    }

    func testSingleAgentLoopMapsChildFailureAndStop() async throws {
        let failedStore = PiAgentSessionStore(fileURL: PiTestSupport.temporaryStateFile())
        let failedSession = try makeSession(store: failedStore)
        let draft = LoopDraft(goal: "Run", structure: .singleAgent, validationCommand: "/usr/bin/true", makerChecker: LoopMakerCheckerConfig(makerName: "Explorer"))
        let maybeFailed = await failedStore.launchSingleAgentLoop(session: failedSession, draft: draft) { _, agentName, task, _, _, _ in
            Self.fakeRun(parentSessionID: failedSession.id, agentName: agentName, task: task, status: .failed, summary: "bad")
        }
        let failed = try XCTUnwrap(maybeFailed)
        XCTAssertEqual(failed.status, .failed)
        XCTAssertEqual(failed.stopReason, .agentFailed)

        let stoppedStore = PiAgentSessionStore(fileURL: PiTestSupport.temporaryStateFile())
        let stoppedSession = try makeSession(store: stoppedStore)
        let maybeStopped = await stoppedStore.launchSingleAgentLoop(session: stoppedSession, draft: draft) { _, agentName, task, _, _, _ in
            Self.fakeRun(parentSessionID: stoppedSession.id, agentName: agentName, task: task, status: .stopped, summary: "stopped")
        }
        let stopped = try XCTUnwrap(maybeStopped)
        XCTAssertEqual(stopped.status, .stopped)
        XCTAssertEqual(stopped.stopReason, .userStopped)
    }

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
            if role == "Analyze" {
                XCTAssertTrue(task.contains("You are completing stage 1 of 2 in an ordered pipeline"))
                XCTAssertTrue(task.contains("Do only the work appropriate for this assigned stage"))
            }
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
        XCTAssertTrue(observedTasks[0].1.contains("one assigned branch/hypothesis"))
        XCTAssertTrue(observedTasks[0].1.contains("Do not coordinate with sibling branches"))
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
        XCTAssertTrue(observedTask.contains("performing discovery and triage"))
        XCTAssertTrue(observedTask.contains("Do not implement fixes unless the loop goal explicitly asks"))
    }

    func testMakerCheckerLoopRejectThenApproveAcrossIterations() async throws {
        let store = PiAgentSessionStore(fileURL: PiTestSupport.temporaryStateFile())
        let session = try makeSession(store: store)
        var responses = ["Maker pass", "REJECT", "Maker revised", "APPROVE"]
        var observedTasks: [(role: String, task: String)] = []
        let draft = LoopDraft(
            goal: "Build safely",
            structure: .makerChecker,
            writeTarget: .artifactMarkdown,
            validationCommand: "/usr/bin/true",
            makerChecker: LoopMakerCheckerConfig(makerName: "Builder", checkerName: "Reviewer", checkerRubric: "approve", maxReviewRounds: 3)
        )

        let maybeRun = await store.launchMakerCheckerLoop(session: session, draft: draft) { _, role, task, _, _, _ in
            observedTasks.append((role, task))
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
        XCTAssertTrue(observedTasks[0].task.contains("implementing one maker pass"))
        XCTAssertTrue(observedTasks[1].task.contains("Agent Deck parses your first line"))
        XCTAssertTrue(observedTasks[1].task.contains("APPROVE, REJECT, ASK_HUMAN, or FAIL"))
        XCTAssertTrue(observedTasks[2].task.contains("Previous checker review to address"))
        XCTAssertTrue(responses.isEmpty)
    }

    func testMakerCheckerLoopMaxRejectsCompletesAsGoalNotMet() async throws {
        let store = PiAgentSessionStore(fileURL: PiTestSupport.temporaryStateFile())
        let session = try makeSession(store: store)
        var responses = ["Maker pass", "REJECT", "Maker revised", "REJECT"]
        let draft = LoopDraft(
            goal: "Build safely",
            structure: .makerChecker,
            writeTarget: .artifactMarkdown,
            validationCommand: "/usr/bin/true",
            makerChecker: LoopMakerCheckerConfig(makerName: "Builder", checkerName: "Reviewer", checkerRubric: "approve", maxReviewRounds: 2)
        )

        let maybeRun = await store.launchMakerCheckerLoop(session: session, draft: draft) { _, role, task, _, _, _ in
            let summary = responses.removeFirst()
            return Self.fakeRun(parentSessionID: session.id, agentName: role, task: task, status: .completed, summary: summary)
        }
        let run = try XCTUnwrap(maybeRun)

        XCTAssertEqual(run.status, .completed)
        XCTAssertEqual(run.stopReason, .maxIterationsReached)
        XCTAssertEqual(run.displayStatusName, "Goal not met")
        XCTAssertEqual(run.currentIteration, 2)
        XCTAssertEqual(run.iterations.map(\.checkerResult), [.reject, .reject])
        XCTAssertTrue(LoopRunRecapCodec.finalText(for: run).contains("Loop final recap — Goal not met"))
        XCTAssertTrue(LoopRunRecapCodec.finalText(for: run).contains("Final checker result: Reject"))
        XCTAssertTrue(responses.isEmpty)
    }

    func testMakerCheckerLoopExplicitCheckerFailIsFailed() async throws {
        let store = PiAgentSessionStore(fileURL: PiTestSupport.temporaryStateFile())
        let session = try makeSession(store: store)
        var responses = ["Maker pass", "FAIL"]
        let draft = LoopDraft(
            goal: "Build safely",
            structure: .makerChecker,
            writeTarget: .artifactMarkdown,
            validationCommand: "/usr/bin/true",
            makerChecker: LoopMakerCheckerConfig(makerName: "Builder", checkerName: "Reviewer", checkerRubric: "approve", maxReviewRounds: 2)
        )

        let maybeRun = await store.launchMakerCheckerLoop(session: session, draft: draft) { _, role, task, _, _, _ in
            let summary = responses.removeFirst()
            return Self.fakeRun(parentSessionID: session.id, agentName: role, task: task, status: .completed, summary: summary)
        }
        let run = try XCTUnwrap(maybeRun)

        XCTAssertEqual(run.status, .failed)
        XCTAssertEqual(run.stopReason, .agentFailed)
        XCTAssertEqual(run.iterations.map(\.checkerResult), [.fail])
        XCTAssertFalse(run.presentsGoalNotMetOutcome)
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
