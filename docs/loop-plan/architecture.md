# Loops Architecture Plan

## Placement in Agent Deck

Loops are an app-managed orchestration layer above normal Pi RPC sessions and native Deck agents. They should not replace Pi's internal model/tool loop, and they should not introduce a separate TypeScript workflow engine.

Loop orchestration lives in the native Agent Deck app. The owning Pi session/transcript holds the loop card, controls, summaries, stop reason, and persisted loop metadata. Actual loop work should run in child/subagent sessions attached to that parent transcript. A single-agent loop may launch one child run per iteration; maker/checker and pipeline loops launch child runs per role/step as needed.

A Loop Run coordinates those child/subagent sessions, validation commands, artifacts, and user checkpoints. Loop run ownership and active-run exclusivity are keyed by the parent Pi session/transcript ID.

## Primary types

The planning model below has been simplified during implementation. The current code keeps structure-specific configuration directly on the definition/draft/run instead of a generic `LoopAgentSlot` / policy graph.

```swift
struct LoopDefinition: Identifiable, Codable, Equatable {
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
}
```

```swift
struct LoopDraft: Equatable {
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
}
```

```swift
struct LoopRun: Identifiable, Codable, Equatable {
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
    var worktreeState: LoopWorktreeState?
}
```

```swift
struct LoopIteration: Identifiable, Codable, Equatable {
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
}
```

```swift
enum LoopWritePolicy: String, Codable {
    case artifact
    case worktree
    case currentCheckout
}
```

```swift
enum LoopRunStatus: String, Codable {
    case running
    case stopping
    case stopped
    case completed
    case failed
    case interrupted
}
```

Iteration state is currently represented by `LoopIteration` fields plus run status/stop reason, not a separate persisted `LoopIterationStatus` enum.

```swift
enum LoopStopReason: String, Codable {
    case success
    case maxIterationsReached
    case userStopped
    case humanInputRequired
    case validationUnavailable
    case validationFailedAfterFinalIteration
    case unsafeWriteTarget
    case agentFailed
    case toolFailed
    case appInterrupted
}
```

Status rules:

- Draft/configuring state belongs to `LoopDraft`, not `LoopRunStatus`; a `LoopRun` exists only after launch.
- Terminal run statuses are `stopped`, `completed`, `failed`, and `interrupted`; terminal runs must have `endedAt` and `stopReason`.
- `completed` pairs with `success`.
- `stopped` pairs with `userStopped` or `humanInputRequired`.
- `failed` pairs with validation/tool/agent/write-target failure stop reasons.
- `interrupted` pairs with `appInterrupted` for app quit/crash while active.
- Failed runs may offer `Retry Failed Iteration` from the loop card.
- Retrying reconstructs the run configuration and starts a fresh `LoopRun`, preserving the failed run rather than overwriting it.

## Services

### LoopCatalogService

Responsibilities:

- load built-in loop templates,
- load user loop definitions,
- load loop assignment metadata,
- resolve loops available to a project/chat using all-project/default and per-project assignments,
- deduplicate or report duplicate names.

### LoopDefinitionPersistence

Responsibilities:

- save user loop definitions,
- update all-project/default and per-project assignment metadata,
- duplicate built-in loops into editable user definitions,
- delete non-built-in loops,
- never edit built-in templates in place.

### Loop run persistence

Loops should be treated as normal Pi session/transcript activity with loop metadata, not as a separate parallel session system. Persist loop run state alongside the owning Pi session/transcript using existing Agent Deck session persistence conventions where possible.

Responsibilities:

- create loop run metadata records attached to the owning parent Pi session/transcript,
- persist iteration state and child/subagent run references as part of session history/metadata,
- persist artifacts metadata using the existing session/artifact storage approach where possible,
- restore completed loop history when the owning session is restored,
- mark active loop runs interrupted if the app exits unexpectedly.

### LoopLaunchResolver

Responsibilities:

- convert a saved definition into a draft,
- apply template defaults,
- validate required fields,
- resolve project and write target,
- prepare launch summary for the modal.

### LoopRunnerService

Responsibilities:

- enforce one active loop per Pi session transcript,
- start/stop loop runs,
- execute iterations by launching and supervising child/subagent sessions,
- coordinate child/subagent roles, validation, artifacts, and worktrees,
- write stop reasons,
- publish UI state updates through AppViewModel.

## Persistence locations

Final paths should be decided during implementation, but the conceptual split should remain:

- Loop definitions are portable, runnable resources: everything needed to launch the loop again must be in the definition.
- Saving a completed unsaved run to the Loop Bank creates a runnable definition from that run's configuration, not a copy of the run transcript.
- Loop runs are app-managed execution history.
- Artifacts belong to the loop run.

Suggested definition path:

```text
~/.pi/agent/loops/<name>.loop.md
```

Project availability should use the same assignment metadata approach as skills, agents, prompts, and MCP resources rather than using project-local loop folders as the primary scope model.

Run state/artifact storage should not use a stale `Application Support/Pilot` namespace. Prefer the existing Agent Deck session/app-support storage conventions. If a loop-specific subdirectory is needed, it should be rooted under the owning Pi session/transcript or the existing Agent Deck app-support root, not under a separate product namespace.

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
- active loop run per selected Pi session/transcript,
- loop run commands: start, stop, retry failed iteration, save, reveal artifacts,
- slash universe extension for loops.

Pause/resume is out of scope for v1. Failed iterations can be retried as a new attempt while preserving the failed child/subagent attempt. Stopped or interrupted loops preserve history/artifacts and can be relaunched from a saved definition or prior settings.
