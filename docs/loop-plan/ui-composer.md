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
Research and Report
Fix Failing Tests
Review and Revise
<saved global loops>
<saved project loops>
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
Report Only
```

Only implemented structures should be enabled. Future structures can be omitted rather than shown disabled.

### 3. Template

Template pre-fills defaults but does not override user edits unexpectedly.

Initial templates:

- Research and Report
- Fix Failing Tests
- Review and Revise
- Implement Task

### 4. Goal

Multiline goal field. Required.

### 5. Agents

Fields depend on structure:

- Single Agent: Primary agent.
- Maker + Checker: Maker and Checker.
- Agent Pipeline: ordered role list.
- Parallel Agents: participants and max parallelism.
- Report Only: investigator/reporter agent.

### 6. Write Target

Required before launch.

Options:

- Report only
- New worktree
- Current checkout

Show the resolved path or artifact directory preview. Current checkout should require explicit confirmation.

### 7. Check Policy

Options vary by template:

- validation command,
- checker approval,
- human approval,
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
- Scope: Global or Project.
- Name.
- Description.

## One active loop per chat

If a chat already has an active loop and the user attempts to start another:

```text
This chat already has an active loop.
[Open Loop] [Stop and Start New] [Cancel]
```

Completed loops can remain in the transcript history. The restriction is one active loop at a time.

## Transcript loop card

A loop run should appear as a durable transcript card.

Running state:

```text
Loop: Fix Failing Tests
Status: Running
Structure: Single Agent
Iteration: 2 / 5
Write target: Worktree
Current step: Validation
```

Actions:

- Open Details
- Stop
- Pause/Resume, when supported
- Save Loop
- Reveal Artifacts
- Reveal Worktree, when applicable

Completed state:

```text
Loop completed
Stop reason: Success
Iterations: 3
Validation: Passed
Changed files: 4
```

Failed/stopped state should show the stop reason plainly.

## Loop inspector

The inspector should show the full iteration timeline:

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

Logs, artifacts, changed files, and validation output belong here rather than flooding the chat transcript.

## Loop Bank screen

Add a dedicated Loops management surface after the composer MVP is proven.

Recommended sections:

- Project Loops
- Global Loops
- Built-in Templates

Actions:

- Create
- Duplicate
- Edit
- Delete non-built-ins
- Assign/unassign project
- Launch

Rows should show:

- name,
- structure,
- template,
- scope,
- default write policy,
- max iterations,
- last run status.

Scope must be shown with text and icon, not color alone.
