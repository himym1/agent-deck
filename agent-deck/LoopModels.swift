import Foundation

nonisolated enum LoopStructureKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case singleAgent
    case makerChecker
    case agentPipeline
    case parallelAgents
    case discoveryTriage
    case humanApproval

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .singleAgent: return "Single Agent"
        case .makerChecker: return "Maker + Checker"
        case .agentPipeline: return "Agent Pipeline"
        case .parallelAgents: return "Parallel Agents"
        case .discoveryTriage: return "Discovery / Triage"
        case .humanApproval: return "Human Approval"
        }
    }
}

nonisolated enum LoopWriteTarget: String, Codable, CaseIterable, Identifiable, Sendable {
    case artifactMarkdown
    case newWorktree
    case currentCheckout

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .artifactMarkdown: return "Artifact / Markdown output"
        case .newWorktree: return "New worktree (explicit coding target)"
        case .currentCheckout: return "Current checkout (explicit/direct)"
        }
    }
}

nonisolated enum LoopRunStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case running
    case stopping
    case stopped
    case completed
    case failed
    case interrupted

    var id: String { rawValue }

    var isActive: Bool {
        self == .running || self == .stopping
    }

    var displayName: String {
        switch self {
        case .running: return "Running"
        case .stopping: return "Stopping"
        case .stopped: return "Stopped"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .interrupted: return "Interrupted"
        }
    }
}

nonisolated enum LoopWorktreeState: String, Codable, Equatable, Sendable {
    case available
    case applied
    case discarded
}

nonisolated enum LoopStopReason: String, Codable, CaseIterable, Identifiable, Sendable {
    case success
    case maxIterationsReached
    case userStopped
    case validationUnavailable
    case validationFailedAfterFinalIteration
    case unsafeWriteTarget
    case humanInputRequired
    case humanRejected
    case agentFailed
    case toolFailed
    case appInterrupted

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .success: return "Success"
        case .maxIterationsReached: return "Max iterations reached"
        case .userStopped: return "User stopped"
        case .validationUnavailable: return "Validation unavailable"
        case .validationFailedAfterFinalIteration: return "Validation failed after final iteration"
        case .unsafeWriteTarget: return "Unsafe write target"
        case .humanInputRequired: return "Human input required"
        case .humanRejected: return "Human rejected"
        case .agentFailed: return "Agent failed"
        case .toolFailed: return "Tool failed"
        case .appInterrupted: return "App interrupted"
        }
    }
}

nonisolated struct LoopMakerCheckerConfig: Codable, Equatable, Hashable, Sendable {
    var makerName: String
    var checkerName: String
    var checkerRubric: String
    var maxReviewRounds: Int

    static let defaultMaxReviewRounds = 3

    init(makerName: String = "", checkerName: String = "", checkerRubric: String = "approve", maxReviewRounds: Int = Self.defaultMaxReviewRounds) {
        self.makerName = makerName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.checkerName = checkerName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.checkerRubric = checkerRubric
        self.maxReviewRounds = max(1, maxReviewRounds)
    }
}

nonisolated struct LoopPipelineConfig: Codable, Equatable, Hashable, Sendable {
    var stageNames: [String]

    init(stageNames: [String] = ["Explorer", "Implementer", "Verifier"]) {
        let trimmed = stageNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        self.stageNames = trimmed.isEmpty ? ["Explorer", "Implementer", "Verifier"] : trimmed
    }
}

nonisolated struct LoopParallelConfig: Codable, Equatable, Hashable, Sendable {
    var branchNames: [String]

    init(branchNames: [String] = ["Branch A", "Branch B"]) {
        let trimmed = branchNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        self.branchNames = trimmed.isEmpty ? ["Branch A", "Branch B"] : trimmed
    }
}

nonisolated struct LoopDiscoveryTriageConfig: Codable, Equatable, Hashable, Sendable {
    var agentName: String
    var classificationPrompt: String

    init(agentName: String = "", classificationPrompt: String = "Classify findings by severity and summarize recommended next action.") {
        self.agentName = agentName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.classificationPrompt = classificationPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Classify findings by severity and summarize recommended next action." : classificationPrompt
    }

    enum CodingKeys: String, CodingKey { case agentName, classificationPrompt }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        agentName = try container.decodeIfPresent(String.self, forKey: .agentName) ?? "Explorer"
        classificationPrompt = try container.decodeIfPresent(String.self, forKey: .classificationPrompt) ?? "Classify findings by severity and summarize recommended next action."
        self = LoopDiscoveryTriageConfig(agentName: agentName, classificationPrompt: classificationPrompt)
    }
}

nonisolated struct LoopHumanApprovalConfig: Codable, Equatable, Hashable, Sendable {
    var checkpointPrompt: String

    init(checkpointPrompt: String = "Review the proposal before continuing.") {
        self.checkpointPrompt = checkpointPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Review the proposal before continuing." : checkpointPrompt
    }
}

nonisolated enum LoopCheckerResult: String, Codable, CaseIterable, Identifiable, Sendable {
    case approve
    case reject
    case askHuman
    case fail

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .approve: return "Approve"
        case .reject: return "Reject"
        case .askHuman: return "Ask human"
        case .fail: return "Fail"
        }
    }
}

nonisolated enum LoopTimelineStepKind: String, Codable, Sendable {
    case makerAct
    case checkerReview
    case pipelineStage
    case parallelBranch
    case discoveryTriage
    case humanApprovalCheckpoint
}

nonisolated struct LoopTimelineEvent: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var step: LoopTimelineStepKind
    var roleName: String
    var note: String
    var timestamp: Date

    init(id: UUID = UUID(), step: LoopTimelineStepKind, roleName: String, note: String, timestamp: Date = Date()) {
        self.id = id
        self.step = step
        self.roleName = roleName
        self.note = note
        self.timestamp = timestamp
    }
}

nonisolated struct LoopDraft: Codable, Equatable, Sendable {
    var goal: String
    var structure: LoopStructureKind
    var writeTarget: LoopWriteTarget
    var maxIterations: Int
    var validationCommand: String
    var makerChecker: LoopMakerCheckerConfig
    var pipeline: LoopPipelineConfig
    var parallel: LoopParallelConfig
    var discoveryTriage: LoopDiscoveryTriageConfig
    var humanApproval: LoopHumanApprovalConfig

    static let defaultMaxIterations = 3

    init(goal: String = "", structure: LoopStructureKind = .singleAgent, writeTarget: LoopWriteTarget = .artifactMarkdown, maxIterations: Int = Self.defaultMaxIterations, validationCommand: String = "", makerChecker: LoopMakerCheckerConfig = LoopMakerCheckerConfig(), pipeline: LoopPipelineConfig = LoopPipelineConfig(), parallel: LoopParallelConfig = LoopParallelConfig(), discoveryTriage: LoopDiscoveryTriageConfig = LoopDiscoveryTriageConfig(), humanApproval: LoopHumanApprovalConfig = LoopHumanApprovalConfig()) {
        self.goal = goal
        self.structure = structure
        self.writeTarget = writeTarget
        self.maxIterations = max(1, maxIterations)
        self.validationCommand = validationCommand
        self.makerChecker = makerChecker
        self.pipeline = pipeline
        self.parallel = parallel
        self.discoveryTriage = discoveryTriage
        self.humanApproval = humanApproval
    }
}

nonisolated enum LoopDefinitionSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case user
    case builtin

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .user: return "User"
        case .builtin: return "Built-in"
        }
    }
}

nonisolated enum LoopDefinitionAvailability: String, Codable, CaseIterable, Identifiable, Sendable {
    case allProjects
    case projectPaths

    var id: String { rawValue }
}

nonisolated struct LoopDefinition: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: String
    var name: String
    var description: String
    var goalTemplate: String
    var structure: LoopStructureKind
    var writeTarget: LoopWriteTarget
    var maxIterations: Int
    var validationCommand: String
    var makerChecker: LoopMakerCheckerConfig
    var pipeline: LoopPipelineConfig
    var parallel: LoopParallelConfig
    var discoveryTriage: LoopDiscoveryTriageConfig
    var humanApproval: LoopHumanApprovalConfig
    var source: LoopDefinitionSource
    var availability: LoopDefinitionAvailability
    var projectPaths: [String]
    var filePath: String?
    var createdAt: Date?
    var updatedAt: Date?

    init(
        id: String = UUID().uuidString,
        name: String,
        description: String = "",
        goalTemplate: String = "",
        structure: LoopStructureKind = .singleAgent,
        writeTarget: LoopWriteTarget = .artifactMarkdown,
        maxIterations: Int = LoopDraft.defaultMaxIterations,
        validationCommand: String = "",
        makerChecker: LoopMakerCheckerConfig = LoopMakerCheckerConfig(),
        pipeline: LoopPipelineConfig = LoopPipelineConfig(),
        parallel: LoopParallelConfig = LoopParallelConfig(),
        discoveryTriage: LoopDiscoveryTriageConfig = LoopDiscoveryTriageConfig(),
        humanApproval: LoopHumanApprovalConfig = LoopHumanApprovalConfig(),
        source: LoopDefinitionSource = .user,
        availability: LoopDefinitionAvailability = .allProjects,
        projectPaths: [String] = [],
        filePath: String? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.goalTemplate = goalTemplate
        self.structure = structure
        self.writeTarget = writeTarget
        self.maxIterations = max(1, maxIterations)
        self.validationCommand = validationCommand
        self.makerChecker = makerChecker
        self.pipeline = pipeline
        self.parallel = parallel
        self.discoveryTriage = discoveryTriage
        self.humanApproval = humanApproval
        self.source = source
        self.availability = availability
        self.projectPaths = projectPaths
        self.filePath = filePath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func isAvailable(in projectPath: String?) -> Bool {
        switch availability {
        case .allProjects:
            return true
        case .projectPaths:
            guard let projectPath else { return false }
            return projectPaths.contains(projectPath)
        }
    }

    func makeDraft() -> LoopDraft {
        LoopDraft(
            goal: goalTemplate,
            structure: structure,
            writeTarget: writeTarget,
            maxIterations: maxIterations,
            validationCommand: validationCommand,
            makerChecker: makerChecker,
            pipeline: pipeline,
            parallel: parallel,
            discoveryTriage: discoveryTriage,
            humanApproval: humanApproval
        )
    }
}

nonisolated struct LoopSaveRequest: Equatable, Sendable {
    var name: String
    var description: String
    var availability: LoopDefinitionAvailability
    var projectPaths: [String]
}

nonisolated struct LoopLaunchRequest: Equatable, Sendable {
    var draft: LoopDraft
    var stopExistingActive: Bool
    var saveRequest: LoopSaveRequest?
}

nonisolated struct LoopArtifact: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var filename: String
    var markdown: String
    var filePath: String?
    var createdAt: Date

    init(id: UUID = UUID(), filename: String, markdown: String, filePath: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.filename = filename
        self.markdown = markdown
        self.filePath = filePath
        self.createdAt = createdAt
    }
}

nonisolated struct LoopValidationResult: Codable, Equatable, Sendable {
    var command: String
    var workingDirectory: String?
    var exitCode: Int?
    var duration: TimeInterval
    var stdout: String
    var stderr: String
    var stdoutPath: String?
    var stderrPath: String?

    init(command: String, workingDirectory: String?, exitCode: Int?, duration: TimeInterval, stdout: String, stderr: String, stdoutPath: String? = nil, stderrPath: String? = nil) {
        self.command = command
        self.workingDirectory = workingDirectory
        self.exitCode = exitCode
        self.duration = duration
        self.stdout = stdout
        self.stderr = stderr
        self.stdoutPath = stdoutPath
        self.stderrPath = stderrPath
    }

    var didPass: Bool { exitCode == 0 }
}

nonisolated struct LoopIteration: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var index: Int
    var startedAt: Date
    var endedAt: Date?
    var summary: String
    var artifacts: [LoopArtifact]
    var validationResult: LoopValidationResult?
    var checkerResult: LoopCheckerResult?
    var timeline: [LoopTimelineEvent]
    var changedFiles: [String]

    init(id: UUID = UUID(), index: Int, startedAt: Date = Date(), endedAt: Date? = nil, summary: String = "", artifacts: [LoopArtifact] = [], validationResult: LoopValidationResult? = nil, checkerResult: LoopCheckerResult? = nil, timeline: [LoopTimelineEvent] = [], changedFiles: [String] = []) {
        self.id = id
        self.index = index
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.summary = summary
        self.artifacts = artifacts
        self.validationResult = validationResult
        self.checkerResult = checkerResult
        self.timeline = timeline
        self.changedFiles = changedFiles
    }

    enum CodingKeys: String, CodingKey {
        case id, index, startedAt, endedAt, summary, artifacts, validationResult, checkerResult, timeline, changedFiles
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        index = try container.decode(Int.self, forKey: .index)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
        summary = try container.decode(String.self, forKey: .summary)
        artifacts = try container.decode([LoopArtifact].self, forKey: .artifacts)
        validationResult = try container.decodeIfPresent(LoopValidationResult.self, forKey: .validationResult)
        checkerResult = try container.decodeIfPresent(LoopCheckerResult.self, forKey: .checkerResult)
        timeline = try container.decodeIfPresent([LoopTimelineEvent].self, forKey: .timeline) ?? []
        changedFiles = try container.decodeIfPresent([String].self, forKey: .changedFiles) ?? []
    }
}

nonisolated struct LoopRun: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var sessionID: UUID
    var projectPath: String?
    var goal: String
    var structure: LoopStructureKind
    var status: LoopRunStatus
    var writeTarget: LoopWriteTarget
    var currentIteration: Int
    var maxIterations: Int
    var validationCommand: String
    var makerChecker: LoopMakerCheckerConfig
    var pipeline: LoopPipelineConfig
    var parallel: LoopParallelConfig
    var discoveryTriage: LoopDiscoveryTriageConfig
    var humanApproval: LoopHumanApprovalConfig
    var startedAt: Date
    var endedAt: Date?
    var stopReason: LoopStopReason?
    var iterations: [LoopIteration]
    var artifactDirectoryPath: String?
    var worktreeState: LoopWorktreeState?
    var transcriptEntryID: UUID

    init(id: UUID = UUID(), sessionID: UUID, projectPath: String?, draft: LoopDraft, startedAt: Date = Date(), artifactDirectoryPath: String? = nil, transcriptEntryID: UUID = UUID()) {
        self.id = id
        self.sessionID = sessionID
        self.projectPath = projectPath
        self.goal = draft.goal.trimmingCharacters(in: .whitespacesAndNewlines)
        self.structure = draft.structure
        self.status = .running
        self.writeTarget = draft.writeTarget
        self.currentIteration = 0
        self.maxIterations = max(1, draft.maxIterations)
        self.validationCommand = draft.validationCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        self.makerChecker = draft.makerChecker
        self.pipeline = draft.pipeline
        self.parallel = draft.parallel
        self.discoveryTriage = draft.discoveryTriage
        self.humanApproval = draft.humanApproval
        self.startedAt = startedAt
        self.endedAt = nil
        self.stopReason = nil
        self.iterations = []
        self.artifactDirectoryPath = artifactDirectoryPath
        self.worktreeState = draft.writeTarget == .newWorktree ? .available : nil
        self.transcriptEntryID = transcriptEntryID
    }

    enum CodingKeys: String, CodingKey {
        case id, sessionID, projectPath, goal, structure, status, writeTarget, currentIteration, maxIterations, validationCommand, makerChecker, pipeline, parallel, discoveryTriage, humanApproval, startedAt, endedAt, stopReason, iterations, artifactDirectoryPath, worktreeState, transcriptEntryID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        sessionID = try container.decode(UUID.self, forKey: .sessionID)
        projectPath = try container.decodeIfPresent(String.self, forKey: .projectPath)
        goal = try container.decode(String.self, forKey: .goal)
        structure = try container.decode(LoopStructureKind.self, forKey: .structure)
        status = try container.decode(LoopRunStatus.self, forKey: .status)
        writeTarget = try container.decode(LoopWriteTarget.self, forKey: .writeTarget)
        currentIteration = try container.decode(Int.self, forKey: .currentIteration)
        maxIterations = try container.decode(Int.self, forKey: .maxIterations)
        validationCommand = try container.decodeIfPresent(String.self, forKey: .validationCommand) ?? ""
        makerChecker = try container.decodeIfPresent(LoopMakerCheckerConfig.self, forKey: .makerChecker) ?? LoopMakerCheckerConfig()
        pipeline = try container.decodeIfPresent(LoopPipelineConfig.self, forKey: .pipeline) ?? LoopPipelineConfig()
        parallel = try container.decodeIfPresent(LoopParallelConfig.self, forKey: .parallel) ?? LoopParallelConfig()
        discoveryTriage = try container.decodeIfPresent(LoopDiscoveryTriageConfig.self, forKey: .discoveryTriage) ?? LoopDiscoveryTriageConfig()
        humanApproval = try container.decodeIfPresent(LoopHumanApprovalConfig.self, forKey: .humanApproval) ?? LoopHumanApprovalConfig()
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
        stopReason = try container.decodeIfPresent(LoopStopReason.self, forKey: .stopReason)
        iterations = try container.decode([LoopIteration].self, forKey: .iterations)
        artifactDirectoryPath = try container.decodeIfPresent(String.self, forKey: .artifactDirectoryPath)
        worktreeState = try container.decodeIfPresent(LoopWorktreeState.self, forKey: .worktreeState)
        transcriptEntryID = try container.decode(UUID.self, forKey: .transcriptEntryID)
    }

    var isActive: Bool { status.isActive }
}

extension PiAgentTranscriptEntry {
    var isLoopTranscriptCard: Bool {
        LoopRunTranscriptCodec.decode(from: self) != nil
    }
}

enum LoopRunTranscriptCodec {
    static let title = "Loop"

    static func rawJSON(for run: LoopRun) -> String? {
        guard let data = try? JSONEncoder.loopRun.encode(run) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode(from entry: PiAgentTranscriptEntry) -> LoopRun? {
        guard entry.role == .status,
              entry.title == title,
              let rawJSON = entry.rawJSON,
              let data = rawJSON.data(using: .utf8) else { return nil }
        return try? JSONDecoder.loopRun.decode(LoopRun.self, from: data)
    }

    static func transcriptText(for run: LoopRun) -> String {
        var lines: [String] = [
            "∞ Loop \(run.status.displayName)",
            "Structure: \(run.structure.displayName)",
            "Write target: \(run.writeTarget.displayName)",
            "Goal: \(run.goal)",
            "Iterations: \(run.currentIteration)/\(run.maxIterations)"
        ]
        if !run.validationCommand.isEmpty {
            lines.append("Validation command: \(run.validationCommand)")
        }
        switch run.structure {
        case .makerChecker:
            lines.append("Maker: \(run.makerChecker.makerName)")
            lines.append("Checker: \(run.makerChecker.checkerName) (report-only)")
            lines.append("Checker rubric: \(run.makerChecker.checkerRubric)")
            if let checkerResult = run.iterations.last?.checkerResult {
                lines.append("Checker result: \(checkerResult.displayName)")
            }
        case .agentPipeline:
            lines.append("Pipeline stages: \(run.pipeline.stageNames.joined(separator: " → "))")
        case .parallelAgents:
            lines.append("Parallel branches: \(run.parallel.branchNames.joined(separator: ", "))")
        case .discoveryTriage:
            lines.append("Classification prompt: \(run.discoveryTriage.classificationPrompt)")
        case .humanApproval:
            lines.append("Checkpoint: \(run.humanApproval.checkpointPrompt)")
        case .singleAgent:
            lines.append("Agent: \(run.makerChecker.makerName)")
        }
        if let timeline = run.iterations.last?.timeline, !timeline.isEmpty {
            lines.append("Timeline: \(timeline.map { $0.roleName }.joined(separator: " → "))")
        }
        if let stopReason = run.stopReason {
            lines.append("Stop reason: \(stopReason.displayName)")
        }
        if let directoryPath = run.artifactDirectoryPath {
            lines.append("Artifact directory: \(directoryPath)")
        }
        if let validation = run.iterations.last?.validationResult {
            lines.append("Validation exit code: \(validation.exitCode.map(String.init) ?? "unavailable")")
            lines.append("Validation duration: \(String(format: "%.2fs", validation.duration))")
        }
        if let changedFiles = run.iterations.last?.changedFiles, !changedFiles.isEmpty {
            lines.append("Changed files: \(changedFiles.joined(separator: ", "))")
        }
        if let artifact = run.iterations.last?.artifacts.first {
            lines.append("")
            lines.append("Artifact: \(artifact.filename)")
            if let filePath = artifact.filePath {
                lines.append("Artifact path: \(filePath)")
            }
            lines.append(artifact.markdown)
        }
        return lines.joined(separator: "\n")
    }

    static func transcriptEntry(for run: LoopRun) -> PiAgentTranscriptEntry {
        PiAgentTranscriptEntry(
            id: run.transcriptEntryID,
            sessionID: run.sessionID,
            role: .status,
            title: title,
            text: transcriptText(for: run),
            rawJSON: rawJSON(for: run),
            timestamp: run.endedAt ?? run.startedAt
        )
    }
}

private nonisolated extension JSONEncoder {
    static var loopRun: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private nonisolated extension JSONDecoder {
    static var loopRun: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
