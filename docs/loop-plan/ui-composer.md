# Loops Composer and UI Plan

## Composer entry point

The primary entry point is `/loops` in the existing slash browser.

The slash browser should show Loops alongside existing resource categories:

```text
Commands
Prompts
Skills
Loops
```

The Loops category should include:

```text
Create New Loop…
Docs + Codebase Sweep
Ticket → Verified Fix
Builder + Reviewer Verification
<available all-project/default loops>
<available project-assigned loops>
```

Selecting a prompt-like resource may insert text into the editor, but selecting a loop should open the Loop Launch Modal. A loop has too many safety-critical settings to launch implicitly from text insertion.

## Create New Loop

`Create New Loop…` opens the launch modal with no source definition and template defaults.

Minimum fields:

- Structure
- Template
- Goal
- Write target
- Limits
- Save option

## Launch saved loop

Selecting a saved loop opens the same modal pre-filled from the saved definition.

The user can adjust runtime fields without changing the saved definition unless they explicitly save changes.

## Loop Launch Modal

Recommended modal sections:

### 1. Header

Show:

- loop name or `Create Loop`,
- project/chat context,
- whether this loop is unsaved or saved.

### 2. Structure

Visible selection:

```text
Single Agent
Maker + Checker
Agent Pipeline
Parallel Agents
Discovery / Triage
Human Approval
```

Only implemented structures should be enabled. Future structures can be omitted rather than shown disabled. As of the current implementation, Single Agent, Maker + Checker, Agent Pipeline, Parallel Agents, and Discovery / Triage launch real child/subagent work. Human Approval is modeled and has a deterministic checkpoint path in the store, but it is not wired as a real launch flow/resumable approval workflow yet.

### 3. Template

Template pre-fills defaults but does not override user edits unexpectedly.

Current v1 public built-ins:

- Docs + Codebase Sweep
- Ticket → Verified Fix
- Builder + Reviewer Verification

Dev/test fixture loops should remain hidden from normal users unless a developer/debug mode intentionally exposes them.

### 4. Goal

Multiline goal field. Required.

### 5. Agents

Fields depend on structure:

- Single Agent: Primary agent.
- Maker + Checker: Maker and Checker.
- Agent Pipeline: ordered role list.
- Parallel Agents: participants and max parallelism.
Some roles can be marked report-only (for example, checker/reviewer roles) even though the overall loop still has an explicit output/write target.

### 6. Write Target

Required before launch.

Options:

- Artifact / Markdown output
- New worktree
- Current checkout

Show the resolved path or artifact directory preview. Current checkout should require explicit confirmation.

### 7. Check Policy

Options vary by template:

- validation command,
- checker approval,
- human-input checkpoint stop (`humanInputRequired`) for the current Human Approval path,
- artifact produced,
- manual stop only.

### 8. Limits

Fields:

- max iterations,
- max runtime,
- ask before next iteration,
- stop on first success.

### 9. Save

Fields:

- Save this loop to Loop Bank.
- Availability: All Projects/default or selected project assignments.
- Name.
- Description.

## One active loop per Pi session transcript

Loop exclusivity is keyed by the Pi session/transcript ID, not by project or window. If a transcript already has an active loop and the user attempts to start another:

```text
This transcript already has an active loop.
[Open Loop] [Stop and Start New] [Cancel]
```

Completed loops can remain in the transcript history. The restriction is one active loop per Pi session transcript at a time.

## Session list loop indicators

Loop UI should integrate with the existing session row status/action cluster rather than adding a separate badge system.

Rules:

- Use SF Symbol `infinity` as the loop symbol.
- Place the `infinity` symbol in the session row lower-right cluster before the existing commit and push symbols.
- Do not add special loop state badge styling there; normal session row dot/state behavior remains unchanged when no loop is running.
- When a loop is actively running, replace the normal three-dot activity indicator with a spinner-style running indicator for the full duration of the loop.
- When the loop completes, stops, or fails terminally, remove the spinner and return to normal session row activity behavior.

This mirrors the Codex-style running-loop affordance while keeping `infinity` as the stable loop symbol.

## Transcript loop card

A loop run should appear as a durable transcript card in the owning parent Pi session. The card is the control and summary surface; detailed child/subagent turns belong in their attached child sessions and the loop inspector, not as unbounded parent transcript text.

Running state:

```text
Loop: Ticket → Verified Fix
Status: Running
Structure: Single Agent
Iteration: 2 / 5
Write target: Worktree
Current step: Validation
```

Actions:

- Open Details
- Stop
- Retry Failed Iteration, when the current iteration failed
- Save Loop
- Reveal Artifacts
- Reveal Worktree, when applicable and not already applied/discarded
- Apply Worktree, when a completed/stopped new-worktree loop has unapplied changes
- Discard Worktree, with confirmation, when a completed/stopped new-worktree loop has unapplied changes

Completed state:

```text
Loop completed
Stop reason: Success
Iterations: 3
Validation: Passed
Changed files: 4
```

Failed/stopped state should show the stop reason plainly. If an iteration failed and is retryable, show `Retry Failed Iteration`; the retry creates a new attempt and keeps the failed child/subagent attempt visible in history.

## Loop inspector

The details/inspector surface should show the full iteration timeline:

```text
Iteration 1
- agent run
- validation failed
- decision: continue

Iteration 2
- agent run
- validation passed
- decision: stop success
```

Child/subagent run links/IDs, logs, artifacts, changed files, and validation output belong here rather than flooding the parent chat transcript. The current implementation uses the loop card's Open Details popover as the read-only details surface and includes per-iteration timeline, artifacts, validation output, changed files, and child run/graph IDs when present in timeline notes or artifacts.

## Loop Bank screen

Add a dedicated Loops management surface after the composer MVP is proven.

Recommended sections:

- Available in Current Project
- All Projects / Default
- Unassigned
- Built-in Templates

Actions:

- Create
- Duplicate
- Edit
- Delete non-built-ins
- Assign/unassign projects
- Launch

Rows should show:

- name,
- structure,
- template,
- availability/assignment,
- default write policy,
- max iterations,
- last run status.

Availability/assignment must be shown with text and icon, not color alone.
