# Loops Execution and Safety Plan

## Execution principle

Loops are app-managed orchestration. The native Agent Deck app owns the run state and decides when to start child/subagent sessions, run checks, continue, stop, or ask the user. Do not add a separate TypeScript workflow engine for loops.

Pi still owns each individual model/tool turn inside a child/subagent session. The parent Pi session/transcript owns the loop card, controls, summaries, and stop reason.

## Runner cycle

The generic loop cycle is:

```text
prepare
→ start iteration
→ run child/subagent step(s)
→ run check
→ decide
→ persist iteration
→ update UI
→ continue or stop
```

## Status and stop reasons

Every terminal loop must end with a durable stop reason. Non-terminal retryable failures use status, not a final stop reason.

Current reasons:

- success,
- max iterations reached,
- user stopped,
- human input required,
- validation unavailable,
- validation failed after final iteration,
- unsafe write target,
- agent failed,
- tool failed,
- app interrupted.

Max-runtime stopping remains a planning idea, but max runtime is not currently implemented.

The final transcript card and run inspector must show the stop reason.

V1 run statuses are:

- `running`,
- `stopping`,
- `stopped`,
- `completed`,
- `failed`,
- `interrupted`.

Terminal statuses are `stopped`, `completed`, `failed`, and `interrupted`; terminal runs must have `endedAt` and `stopReason`. Failed terminal runs may offer `Retry Failed Iteration` when safe; retry creates a fresh loop run and preserves the failed run.

## Write policies

### Artifact / Markdown output

This is the explicit output target for loops whose useful result is a report, plan, audit, or other artifact. The whole loop is not called `report-only`; individual roles/steps may be report-only.

Allowed writes:

- loop artifacts directory,
- loop run metadata.

Disallowed writes unless a coding write target is separately selected:

- project files,
- current checkout,
- worktree files unless explicitly part of artifact storage.

### New worktree

Explicit user choice for coding loops. Do not silently default to this or any other write target.

Requirements:

- show the worktree path before or during launch where possible,
- run agent work inside the worktree,
- run validation inside the worktree,
- keep current checkout untouched,
- show final diff/changed-file summary where available,
- expose explicit Apply Worktree and Discard Worktree actions after completion/stopping; never apply or discard implicitly.

### Current checkout

Explicit user choice for coding loops. Do not silently default to this or any other write target.

Recommended gates:

- show exact checkout path,
- warn if git state is dirty,
- require confirmation,
- provide changed file summary.

## Validation commands

Validation commands should be explicit user/configured inputs, not hidden template behavior.

For each validation command capture:

- command string,
- working directory,
- exit code,
- duration,
- capped stdout/stderr,
- full output artifact path when needed.

The runner should feed a structured summary into the next iteration rather than dumping unlimited raw output into agent context.

## Agent roles

### Single Agent

One primary role acts and may receive validation summaries between iterations.

### Maker + Checker

Maker may write according to the loop write policy.

Checker should default to report-only. Checker output should be structured as:

- approve,
- reject with reasons,
- ask human,
- fail.

### Pipeline

Each role receives only the necessary handoff summary and artifacts, not unbounded full history.

### Parallel Agents

Parallel coding agents require isolated worktrees. Do not run multiple writing agents in the same checkout. The current implementation runs parallel loop branches through the native parallel child-agent graph and forces child expected outcomes from the selected loop write target.

## State handoff

Between iterations, persist:

- goal,
- iteration summary,
- validation summary,
- changed file summary,
- checker result,
- artifacts.

Prefer rolling summaries and current artifacts over injecting stale file contents into long-lived prompts.

## User interruption and failure recovery

Stop should be available from the transcript card and inspector.

If the user launches a new loop in a chat that already has an active loop, the launch flow should offer to stop the current loop first. Confirming records the current run as `userStopped`, preserves its partial state/artifacts, and then starts the new run.

On user stop:

- cancel in-flight child/subagent work if possible,
- mark run `stopped`,
- record `userStopped`,
- preserve artifacts and partial iteration state.

On child/subagent failure or tool failure:

- mark the current iteration as failed,
- preserve the failed child/subagent run link, logs, artifacts, and validation output,
- show the precise failure reason on the loop card and inspector,
- offer `Retry Failed Iteration` for v1.

`Retry Failed Iteration` creates a fresh loop run from the failed run's configuration. It should not erase or overwrite the failed run. If retry cannot be prepared safely, the failed run remains preserved with its stop reason and artifacts.

## Restart/resume

First release should not auto-resume loops after app restart.

Recommended first behavior:

- completed runs are persisted,
- active runs interrupted by app exit are marked interrupted/failed,
- user can relaunch from saved definition or run settings.

Manual resume can be added later. Pause/resume is not part of v1; v1 supports Stop, failed-iteration retry, preserves history/artifacts, and allows relaunch from a saved definition or prior settings.

## Background/scheduled loops

Out of scope for first release.

Do not add loops that run while the user is absent until explicit write target, notification, credential, and conflict policies are designed.
