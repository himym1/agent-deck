# Loops Product Model

## User-facing concepts

| Concept | Meaning |
|---|---|
| Loop | A bounded iterative workflow launched from a chat. |
| Loop Bank | The reusable catalog of saved loops. |
| Loop Definition | A saved loop configuration. |
| Loop Draft | The temporary configuration in the launch modal. |
| Loop Run | One execution of a loop in one chat. |
| Iteration | One pass through the loop's act/check/decide cycle. |
| Structure | The agent organization pattern: single agent, maker/checker, pipeline, etc. |
| Template | A pre-filled starting point for a reusable loop configuration. |
| Write Target | Where the loop may write: report artifacts, new worktree, or current checkout. |
| Stop Reason | The durable reason a loop ended. |

## Loop structures

Structures are user-visible because they change cost, safety, autonomy, and review behavior.

### Single Agent

One agent repeatedly acts, checks, and decides whether to continue.

Best for:

- simple test-fix loops,
- focused cleanup,
- small refactors,
- report generation with a completeness check.

Shape:

```text
Primary agent acts
→ check result
→ continue or stop
```

### Maker + Checker

One agent makes changes and a second agent reviews or verifies them.

Best for:

- quality-sensitive coding tasks,
- PR preparation,
- refactors,
- security or correctness review.

Shape:

```text
Maker acts
→ Checker reviews/tests
→ revise, ask human, or stop
```

The checker should be report-only by default unless the user explicitly grants write access.

### Agent Pipeline

Multiple roles run in a fixed sequence, with a gate at the end of each iteration.

Best for:

- issue-to-PR workflows,
- research → implement → verify flows,
- migrations,
- larger tasks requiring role separation.

Shape:

```text
Explorer
→ Implementer
→ Verifier
→ continue or stop
```

### Parallel Agents

Multiple agents work concurrently, normally in isolated worktrees, then a verifier or user selects the result.

Best for:

- competing fixes,
- independent hypotheses,
- broad investigation,
- high-uncertainty tasks.

Shape:

```text
Agent A in worktree A
Agent B in worktree B
Agent C in worktree C
→ compare
→ select/apply/stop
```

In the current implementation, parallel loops run as native child-agent graph runs. New-worktree parallel loops use isolated worktrees for child writes; artifact loops keep child roles report-only.

### Discovery / Triage

A loop inspects signals, groups findings, and recommends or launches follow-up action.

Best for:

- GitHub issue triage,
- CI failure triage,
- dependency or release readiness reports,
- daily health reports.

Scheduled/background execution is out of scope for the first release.

### Human Approval

The loop pauses at explicit checkpoints before continuing. In the current implementation this is a checkpoint/stop path only: the run records `humanInputRequired` and preserves an artifact; continuing/resuming from that checkpoint remains future work.

Best for:

- destructive operations,
- ambiguous product choices,
- branch/apply decisions,
- external side effects.

Shape:

```text
Agent proposes
→ user approves/chooses
→ agent continues (future resume behavior)
```

## Report-only roles and steps

`Report-only` is not a loop structure and not a whole-loop write target. A loop should always have an explicit useful output target: for example a Markdown artifact, a worktree, or the current checkout.

Individual roles or steps may be report-only. Examples:

- a checker in a Maker + Checker loop reviews without editing,
- an explorer in a pipeline writes findings as artifacts before an implementer acts,
- a research loop writes a Markdown artifact as its useful output.

This avoids the ambiguous state where an entire loop is labeled `Report Only` even though producing an artifact is already a concrete output.

## Built-in loops and test fixtures

No built-in loops are currently bundled. User-facing loop definitions are created by users in Loop Bank.

### Dev/test fixture loops

Use tiny deterministic fixtures to validate the runner without depending on broad model quality:

1. **Artifact Smoke Fixture** — launches one child/subagent and writes a small Markdown artifact.
2. **Retry Failure Fixture** — intentionally fails one iteration, preserves the failed attempt, then verifies `Retry Failed Iteration` creates a new attempt.
3. **Validation Fixture** — runs a configurable command that fails once then passes, proving continue/stop behavior.
4. **Write Target Fixture** — writes a known file only when worktree/current-checkout is explicitly selected, proving artifact-only and coding write-target separation.

These fixtures are acceptance tools for implementation slices, not public product promises.

## Scoping and assignment model

Saved loops should follow the same resource-management approach as skills, agents, prompts, and MCP resources:

- The Loop Bank is a global resource list, not a project-filtered file browser.
- A loop can be enabled for all projects/default use or assigned to specific projects.
- A loop with no all-project/default enablement and no project assignment is still visible in management views, but appears unassigned/inactive.
- `/loops` in a project/chat shows loops available to that context: all-project/default loops plus loops assigned to the current project.
- Built-in templates are read-only; users duplicate or save a customized copy before editing.

Library-style imported loop catalogs can be added later if needed, but should use the same assignment semantics rather than a separate scoping model.
