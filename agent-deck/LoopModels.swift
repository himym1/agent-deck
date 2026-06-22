import Foundation

nonisolated enum LoopStructureKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case singleAgent

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .singleAgent: return "Single Agent"
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

nonisolated enum LoopStopReason: String, Codable, CaseIterable, Identifiable, Sendable {
    case success
    case maxIterationsReached
    case userStopped
    case validationUnavailable
    case validationFailedAfterFinalIteration
    case unsafeWriteTarget
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
        case .toolFailed: return "Tool failed"
        case .appInterrupted: return "App interrupted"
        }
    }
}

nonisolated struct LoopDraft: Codable, Equatable, Sendable {
    var goal: String
    var structure: LoopStructureKind
    var writeTarget: LoopWriteTarget
    var maxIterations: Int
    var validationCommand: String

    static let defaultMaxIterations = 3

    init(goal: String = "", structure: LoopStructureKind = .singleAgent, writeTarget: LoopWriteTarget = .artifactMarkdown, maxIterations: Int = Self.defaultMaxIterations, validationCommand: String = "") {
        self.goal = goal
        self.structure = structure
        self.writeTarget = writeTarget
        self.maxIterations = max(1, maxIterations)
        self.validationCommand = validationCommand
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
            validationCommand: validationCommand
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
    var changedFiles: [String]

    init(id: UUID = UUID(), index: Int, startedAt: Date = Date(), endedAt: Date? = nil, summary: String = "", artifacts: [LoopArtifact] = [], validationResult: LoopValidationResult? = nil, changedFiles: [String] = []) {
        self.id = id
        self.index = index
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.summary = summary
        self.artifacts = artifacts
        self.validationResult = validationResult
        self.changedFiles = changedFiles
    }

    enum CodingKeys: String, CodingKey {
        case id, index, startedAt, endedAt, summary, artifacts, validationResult, changedFiles
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
    var startedAt: Date
    var endedAt: Date?
    var stopReason: LoopStopReason?
    var iterations: [LoopIteration]
    var artifactDirectoryPath: String?
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
        self.startedAt = startedAt
        self.endedAt = nil
        self.stopReason = nil
        self.iterations = []
        self.artifactDirectoryPath = artifactDirectoryPath
        self.transcriptEntryID = transcriptEntryID
    }

    enum CodingKeys: String, CodingKey {
        case id, sessionID, projectPath, goal, structure, status, writeTarget, currentIteration, maxIterations, validationCommand, startedAt, endedAt, stopReason, iterations, artifactDirectoryPath, transcriptEntryID
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
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
        stopReason = try container.decodeIfPresent(LoopStopReason.self, forKey: .stopReason)
        iterations = try container.decode([LoopIteration].self, forKey: .iterations)
        artifactDirectoryPath = try container.decodeIfPresent(String.self, forKey: .artifactDirectoryPath)
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
