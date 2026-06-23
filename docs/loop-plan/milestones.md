# Loops End-to-End Milestones

## Strategy

Build vertical slices. Each milestone should produce a working user path that can be tested before the next milestone starts.

Avoid building all models, all UI, and all runner behavior before anything works. The goal is to prove the full path early, then deepen it.

## Milestone 1: Unsaved loop skeleton

Goal: launch one unsaved loop from the composer and complete it with a stop reason.

Recommended first loop: minimal Single Agent that produces an artifact/Markdown output. During early construction this used the Artifact Smoke Fixture; current implementation launches a real child/subagent for Single Agent loops while keeping the fixture for deterministic tests.

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
- One active loop per Pi session/transcript enforcement.
- Minimal native runner that can launch/supervise child/subagent work and complete a loop run.
- Transcript loop card.
- Artifact Smoke Fixture for deterministic local validation.

Exit criteria:

- A loop can run without being saved.
- Starting a second active loop in the same Pi session/transcript offers to stop the current loop first.
- Completed run displays status and stop reason.
- Artifact Smoke Fixture completes without requiring a polished public built-in.

## Milestone 2: Save to Loop Bank

Goal: save a configured or completed loop for reuse.

User path:

```text
completed unsaved loop
→ Save Loop
→ choose All Projects/default or project assignment
→ saved loop appears in /loops
→ relaunch saved loop
```

Deliverables:

- Loop Definition persistence.
- Loop Bank catalog resolution.
- All-project/default and project-assigned saved loops.
- Save Loop flow from launch modal and completed loop card.
- Relaunch saved loop through the same launch modal.
- Docs + Codebase Sweep, Ticket → Verified Fix, and Builder + Reviewer Verification built-ins saved as read-only public templates.

Exit criteria:

- All-project/default loops appear in every project context.
- Project-assigned loops appear in `/loops` only for their assigned project contexts while still remaining visible in Loop Bank management.
- Saved loop creates a new draft before launch.
- Built-ins can be duplicated/customized but not edited in place.

## Milestone 3: Artifact-output runner

Goal: run an agent-backed loop whose useful output is an artifact, such as a Markdown report.

Deliverables:

- Child/subagent execution path for artifact-output loops.
- Artifact directory per loop run.
- Artifact listing in loop card/inspector.
- Artifact-producing public built-in.
- Enforcement that artifact-output loops write only to the loop artifact directory unless a later coding write target is explicitly chosen.

Exit criteria:

- Report artifact is produced and visible.
- Project files are unchanged.
- Artifact-producing built-in completes successfully in a smoke run.
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
- Iteration loop: launch child/subagent act step → check → decide.
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
- Explicit worktree path preview before launch where possible.
- Agent execution inside worktree.
- Validation runs inside worktree.
- Final diff summary.
- Reveal/apply/discard controls backed by existing worktree patch services.

Current implementation status:

- New-worktree loop runs keep the current checkout untouched and run validation in the worktree.
- The loop card exposes Reveal Worktree while the worktree is available.
- The loop card exposes Apply Worktree and Discard Worktree after completion/stopping. Apply refuses dirty parent repositories via the shared worktree service; Discard requires confirmation. Applied/discarded state is persisted on the loop run so stale actions disappear.

Exit criteria:

- Current checkout remains untouched.
- Changed files are visible in final summary/details where available.
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

- Maker child/subagent run completes before checker child/subagent run starts.
- Checker approval stops successfully.
- Checker rejection triggers another maker iteration.
- Checker remains report-only unless explicitly configured otherwise.

## Milestone 7: Loop Bank management screen

Goal: provide durable management outside the composer.

Deliverables:

- Loops sidebar/screen.
- List by availability/assignment: Current Project, All Projects/default, Unassigned, Built-in.
- Create, duplicate, edit, delete non-builtins.
- Assign/unassign loops to projects.
- Last run summary.

Exit criteria:

- Users can manage loops without entering the composer.
- Availability/assignment is visible with icon and text.

## Milestone 8: Additional structures, checkpoints, and templates

Goal: extend the proven foundation. Human Approval is currently a terminal checkpoint/stop path, not a continuing approval workflow.

Current implementation status:

1. Agent Pipeline — implemented with ordered selectable child-agent stages and sequential execution.
2. Maker + Checker — implemented with selectable maker/checker agents, report-only checker behavior, approval/rejection/ask-human/fail decisions, and max review rounds.
3. Discovery/Triage — implemented with a selectable triage agent and Markdown artifact output.
4. Parallel Agents — implemented through the native parallel child-agent graph, including worktree-aware expected outcomes.
5. Human Approval checkpoints — implemented as a stop/checkpoint card path, not as a continuing approval/resume workflow.
6. Single Agent — implemented with selectable agent execution through a real child/subagent run; deterministic smoke execution remains available for local fixtures/tests.

Exit criteria:

- Each new structure has a narrow end-to-end path and focused tests.
