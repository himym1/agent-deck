# Loops End-to-End Milestones

## Strategy

Build vertical slices. Each milestone should produce a working user path that can be tested before the next milestone starts.

Avoid building all models, all UI, and all runner behavior before anything works. The goal is to prove the full path early, then deepen it.

## Milestone 0: Chains retirement inventory

Goal: confirm and remove the unreleased user-facing Chains product surface.

Deliverables:

- Inventory all `chain`, `Chain`, and `.chain.md` references.
- Decide whether any internal sequence status code must remain.
- Remove or update stale docs.
- Add a deprecation warning or ignore path for old `.chain.md` files if needed.

Exit criteria:

- Product docs no longer present Chains as a supported resource.
- Remaining chain references are either removed, internal-only, or explicitly historical.

## Milestone 1: Unsaved loop skeleton

Goal: launch one unsaved loop from the composer and complete it with a stop reason.

Recommended first loop: Report Only or minimal Single Agent.

User path:

```text
/loops
→ Create New Loop
→ choose structure/template
→ launch
→ loop card appears
→ loop completes
→ stop reason shown
```

Deliverables:

- Loop models for draft/run/iteration/stop reason.
- `/loops` category or row in the composer slash browser.
- Create New Loop launch modal.
- One active loop per chat enforcement.
- Minimal runner that can complete a loop run.
- Transcript loop card.

Exit criteria:

- A loop can run without being saved.
- A second active loop cannot start in the same chat.
- Completed run displays status and stop reason.

## Milestone 2: Save to Loop Bank

Goal: save a configured or completed loop for reuse.

User path:

```text
completed unsaved loop
→ Save Loop
→ choose Global or Project
→ saved loop appears in /loops
→ relaunch saved loop
```

Deliverables:

- Loop Definition persistence.
- Loop Bank catalog resolution.
- Global and project saved loops.
- Save Loop flow from launch modal and completed loop card.
- Relaunch saved loop through the same launch modal.

Exit criteria:

- Global loops appear in every project context.
- Project loops appear only for the assigned project.
- Saved loop creates a new draft before launch.

## Milestone 3: Real report-only runner

Goal: run an agent-backed report-only loop that writes artifacts only.

Deliverables:

- Agent execution path for report-only loops.
- Artifact directory per loop run.
- Artifact listing in loop card/inspector.
- Enforcement that report-only loops do not write project files.

Exit criteria:

- Report artifact is produced and visible.
- Project files are unchanged.
- Failures produce durable stop reasons.

## Milestone 4: Single-agent validation loop

Goal: let validation results drive iteration.

User path:

```text
Create Single Agent loop
→ set validation command
→ max iterations 3
→ launch
→ validation passes/fails
→ loop stops or continues
```

Deliverables:

- Validation command policy.
- Validation result capture and output capping.
- Iteration loop: act → check → decide.
- Max iteration stop reason.
- User stop behavior.

Exit criteria:

- Passing validation stops the loop.
- Failing validation continues until max iterations.
- User stop records `userStopped`.

## Milestone 5: Worktree coding loop

Goal: allow a coding loop to write safely in a visible worktree.

Deliverables:

- Worktree write target option.
- Explicit worktree path preview before launch.
- Agent execution inside worktree.
- Validation runs inside worktree.
- Final diff summary.
- Reveal/apply controls, if supported by existing worktree services.

Exit criteria:

- Current checkout remains untouched.
- Changed files are visible in final summary.
- Validation command runs in the worktree.

## Milestone 6: Maker + Checker loop

Goal: coordinate two agent roles in one loop.

Deliverables:

- Structure-specific modal fields for maker and checker.
- Checker rubric.
- Checker result model: approve, reject, ask human, fail.
- Revision loop after rejection.
- Max review rounds.

Exit criteria:

- Maker runs before checker.
- Checker approval stops successfully.
- Checker rejection triggers another maker iteration.
- Checker remains report-only unless explicitly configured otherwise.

## Milestone 7: Loop Bank management screen

Goal: provide durable management outside the composer.

Deliverables:

- Loops sidebar/screen.
- List by scope: Project, Global, Built-in.
- Create, duplicate, edit, delete non-builtins.
- Assign/unassign project loops.
- Last run summary.

Exit criteria:

- Users can manage loops without entering the composer.
- Scope is visible with icon and text.

## Milestone 8: Additional structures and templates

Goal: extend the proven foundation.

Recommended order:

1. Agent Pipeline
2. Parallel Agents with worktrees
3. Discovery/Triage
4. Human Approval checkpoints

Exit criteria:

- Each new structure has a narrow end-to-end path and focused tests.
