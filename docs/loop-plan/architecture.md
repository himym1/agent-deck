# Loops Architecture Plan

## Placement in Agent Deck

Loops are an app-managed orchestration layer above normal Pi RPC sessions and native Deck agents. They should not replace Pi's internal model/tool loop. A Loop Run coordinates one or more agent sessions, validation commands, artifacts, and user checkpoints.

## Primary types

```swift
struct LoopDefinition: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var description: String
    var source: ResourceSource
    var structure: LoopStructureKind
    var template: LoopTemplateKind
    var goalTemplate: String
    var agentSlots: [LoopAgentSlot]
    var writePolicy: LoopWritePolicy
    var checkPolicy: LoopCheckPolicy
    var stopPolicy: LoopStopPolicy
    var statePolicy: LoopStatePolicy
    var createdAt: Date
    var updatedAt: Date
}
```

```swift
struct LoopDraft: Equatable {
    var sourceDefinitionID: String?
    var name: String
    var goal: String
    var projectPath: String?
    var structure: LoopStructureKind
    var template: LoopTemplateKind
    var agentSlots: [LoopAgentSlot]
    var writePolicy: LoopWritePolicy
    var checkPolicy: LoopCheckPolicy
    var stopPolicy: LoopStopPolicy
    var saveAfterLaunch: Bool
    var saveScope: LoopSaveScope
}
```

```swift
struct LoopRun: Identifiable, Codable, Equatable {
    var id: String
    var sessionID: String
    var definitionID: String?
    var projectPath: String?
    var goal: String
    var structure: LoopStructureKind
    var template: LoopTemplateKind
    var status: LoopRunStatus
    var writeTarget: LoopWriteTarget
    var currentIteration: Int
    var maxIterations: Int
    var startedAt: Date
    var endedAt: Date?
    var stopReason: LoopStopReason?
    var iterations: [LoopIteration]
}
```

```swift
struct LoopIteration: Identifiable, Codable, Equatable {
    var id: String
    var index: Int
    var status: LoopIterationStatus
    var startedAt: Date
    var endedAt: Date?
    var agentRunIDs: [String]
    var validationResult: LoopValidationResult?
    var changedFiles: [String]
    var artifacts: [LoopArtifact]
    var decision: LoopIterationDecision
}
```

## Enums

```swift
enum LoopStructureKind: String, Codable, CaseIterable {
    case singleAgent
    case makerChecker
    case agentPipeline
    case parallelAgents
    case discoveryTriage
    case humanApproval
    case reportOnly
}
```

```swift
enum LoopWritePolicy: String, Codable {
    case reportOnly
    case worktree
    case currentCheckout
}
```

```swift
enum LoopStopReason: String, Codable {
    case success
    case maxIterationsReached
    case maxRuntimeReached
    case userStopped
    case humanInputRequired
    case validationUnavailable
    case validationFailedAfterFinalIteration
    case unsafeWriteTarget
    case agentFailed
    case toolFailed
}
```

## Services

### LoopCatalogService

Responsibilities:

- load built-in loop templates,
- load global loop definitions,
- load project loop definitions,
- resolve visible loops for a project/chat,
- deduplicate or report duplicate names.

### LoopDefinitionPersistence

Responsibilities:

- save global loops,
- save project loops,
- duplicate built-in loops into editable user definitions,
- delete non-built-in loops,
- never edit built-in templates in place.

### LoopRunStore

Responsibilities:

- create run records,
- persist iteration state,
- persist artifacts metadata,
- restore completed run history,
- mark active runs interrupted if the app exits unexpectedly.

### LoopLaunchResolver

Responsibilities:

- convert a saved definition into a draft,
- apply template defaults,
- validate required fields,
- resolve project and write target,
- prepare launch summary for the modal.

### LoopRunnerService

Responsibilities:

- enforce one active loop per chat,
- start/stop/pause/resume loop runs,
- execute iterations,
- coordinate agents, validation, artifacts, and worktrees,
- write stop reasons,
- publish UI state updates through AppViewModel.

## Persistence locations

Final paths should be decided during implementation, but the conceptual split should remain:

- Loop definitions are portable resources.
- Loop runs are app-managed execution history.
- Artifacts belong to the loop run.

Suggested definition paths:

```text
~/.pi/agent/loops/<name>.loop.md
<project>/.pi/loops/<name>.loop.md
```

Suggested app-managed run paths:

```text
Application Support/Pilot/LoopRuns/<session-id>/<loop-run-id>/run.json
Application Support/Pilot/LoopRuns/<session-id>/<loop-run-id>/artifacts/
```

## Markdown vs JSON definitions

Preferred definition format: `.loop.md` with frontmatter.

Reasoning:

- user-readable,
- easy to diff,
- can include long natural-language instructions,
- matches existing Markdown-oriented resources.

Run state should be JSON because it is structured execution state, not a resource users are expected to edit.

## AppViewModel integration

AppViewModel should remain the single UI source of truth. Loop services should be owned or coordinated from AppViewModel, but the runner logic should live in dedicated services to keep the view model from becoming the workflow engine.

Expected AppViewModel additions:

- visible loops for selected project,
- current loop draft/modal state,
- active loop run per selected session,
- loop run commands: start, stop, save, reveal artifacts,
- slash universe extension for loops.
