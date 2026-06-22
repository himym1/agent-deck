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
| Template | A pre-filled starting point such as Fix Failing Tests or Research and Report. |
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

This structure should not be first release unless the single-agent and worktree foundations are already stable.

### Discovery / Triage

A loop inspects signals, groups findings, and recommends or launches follow-up action.

Best for:

- GitHub issue triage,
- CI failure triage,
- dependency or release readiness reports,
- daily health reports.

Scheduled/background execution is out of scope for the first release.

### Human Approval

The loop pauses at explicit checkpoints before continuing.

Best for:

- destructive operations,
- ambiguous product choices,
- branch/apply decisions,
- external side effects.

Shape:

```text
Agent proposes
→ user approves/chooses
→ agent continues
```

### Report Only

The loop investigates and writes artifacts, but never modifies project files.

Best for:

- research,
- audits,
- architecture review,
- migration plans,
- risk analysis.

This can be implemented as a structure or as a write policy. In the UI, it should be visible as a safe starting option.

## Built-in templates

Initial templates should pre-fill drafts rather than define separate execution engines.

Recommended first templates:

1. Research and Report
2. Fix Failing Tests
3. Review and Revise
4. Implement Task

Later templates:

- Refactor Safely
- Issue to PR
- CI Failure Triage
- Release Readiness

## Scoping model

Saved loops should support:

- Built-in templates: read-only, duplicate/save to customize.
- Global loops: visible across projects.
- Project loops: visible for a specific project.

Library loops can be added later if needed, but they add assignment complexity and should not be part of the first implementation.
