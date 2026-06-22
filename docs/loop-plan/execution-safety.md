# Loops Execution and Safety Plan

## Execution principle

Loops are app-managed orchestration. The app owns the run state and decides when to start agents, run checks, continue, stop, or ask the user.

Pi still owns each individual model/tool turn inside an agent session.

## Runner cycle

The generic loop cycle is:

```text
prepare
→ start iteration
→ run agent step(s)
→ run check
→ decide
→ persist iteration
→ update UI
→ continue or stop
```

## Stop reasons

Every loop must end with a durable stop reason.

Initial reasons:

- success,
- max iterations reached,
- max runtime reached,
- user stopped,
- human input required,
- validation unavailable,
- validation failed after final iteration,
- unsafe write target,
- agent failed,
- tool failed.

The final transcript card and run inspector must show the stop reason.

## Write policies

### Report only

Allowed writes:

- loop artifacts directory,
- loop run metadata.

Disallowed writes:

- project files,
- current checkout,
- worktree files unless explicitly part of artifact storage.

### New worktree

Default for coding loops.

Requirements:

- show the worktree path before launch,
- run agent work inside the worktree,
- run validation inside the worktree,
- keep current checkout untouched,
- show final diff summary.

### Current checkout

Allowed only with explicit user choice.

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

Parallel coding agents require isolated worktrees. Do not run multiple writing agents in the same checkout.

## State handoff

Between iterations, persist:

- goal,
- iteration summary,
- validation summary,
- changed file summary,
- checker result,
- artifacts.

Prefer rolling summaries and current artifacts over injecting stale file contents into long-lived prompts.

## User interruption

Stop should be available from the transcript card and inspector.

On stop:

- cancel in-flight agent work if possible,
- mark run `stopped`,
- record `userStopped`,
- preserve artifacts and partial iteration state.

## Restart/resume

First release should not auto-resume loops after app restart.

Recommended first behavior:

- completed runs are persisted,
- active runs interrupted by app exit are marked interrupted/failed,
- user can relaunch from saved definition or run settings.

Manual resume can be added later.

## Background/scheduled loops

Out of scope for first release.

Do not add loops that run while the user is absent until explicit write target, notification, credential, and conflict policies are designed.
