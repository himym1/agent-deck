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
| Template | A pre-filled starting point such as Docs + Codebase Sweep or Ticket → Verified Fix. |
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

Built-in loops should be polished user-facing templates inspired by published loop patterns, but adapted to Agent Deck's product model and safety constraints. They should pre-fill drafts rather than define separate execution engines.

Keep two sets separate:

1. **User-facing built-in loops** — visible in `/loops` and Loop Bank as read-only templates users can duplicate/customize.
2. **Dev/test fixture loops** — local deterministic fixtures used while building the runner; they should not be presented as polished product templates.

### Current v1 built-in loops

These are the product-refined built-in definitions currently present in Agent Deck. They are saved templates, not separate execution engines. Do not replace them with older planning names without checking git history and product intent.

1. **Docs + Codebase Sweep**
   - Structure: Discovery / Triage.
   - Output target: Artifact / Markdown output.
   - Purpose: inspect docs and repository state, classify findings as blockers/follow-ups/notes, and recommend the safest next action.
   - Success: triage artifact is visible, validation/check commands run when configured, and the run ends with a durable stop reason.

2. **Ticket → Verified Fix**
   - Structure: Agent Pipeline.
   - Output target: Artifact / Markdown output by default; users can explicitly choose New worktree or Current checkout at launch when they want coding writes.
   - Purpose: move from ticket context through implementation and verification with ordered agent handoff.
   - Success: ordered child-agent stages complete, validation evidence is preserved, and the final summary explains changes/risks.

3. **Builder + Reviewer Verification**
   - Structure: Maker + Checker.
   - Output target: Artifact / Markdown output by default; users can explicitly choose New worktree or Current checkout at launch when they want coding writes.
   - Purpose: have a builder make changes and a reviewer/checker verify them before success.
   - Success: maker child run completes before checker child run, checker approval stops successfully, rejection triggers another maker iteration up to the configured review limit.

### Later built-in loops

- Review and Revise / Maker + Checker.
- Refactor Safely.
- Issue to PR.
- CI Failure Triage.
- Release Readiness.

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
