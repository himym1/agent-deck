# Loops Testing Plan

## Test strategy

Each milestone should include focused unit tests and at least one integration or smoke test for the end-to-end path it introduces.

Avoid waiting until all loop structures exist before testing. Every vertical slice should be independently shippable or safely hidden.

## Built-in and fixture acceptance strategy

Use separate public built-ins and dev/test fixtures:

- Public built-ins prove the product experience: Docs + Codebase Sweep, Ticket → Verified Fix, and Builder + Reviewer Verification.
- Dev/test fixtures prove runner mechanics deterministically: Artifact Smoke Fixture, Retry Failure Fixture, Validation Fixture, and Write Target Fixture.

Release success should require at least:

- Docs + Codebase Sweep built-in launches, completes, writes a visible triage artifact, saves to Loop Bank, and relaunches.
- Artifact Smoke Fixture passes in automated or smoke validation.
- Retry Failure Fixture proves failed attempts are preserved and retry creates a new attempt.
- Validation Fixture proves pass/fail/continue/stop behavior.
- Write Target Fixture proves artifact-output loops do not modify project files and coding loops require explicit write target choice.

## Milestone 1: unsaved loop skeleton

Test cases:

- `/loops` category appears in slash universe.
- Create New Loop opens a draft modal.
- Draft requires goal and write target.
- Launch creates a LoopRun attached to the parent Pi session/transcript.
- A Pi session/transcript offers to stop the current loop before starting a second active loop.
- Loop card renders running and completed states.
- Completed run records a stop reason.

## Milestone 2: Loop Bank

Test cases:

- Save loop as All Projects/default.
- Save loop assigned to a project.
- All-project/default loop appears across project contexts.
- Project-assigned loop appears in `/loops` only for that project context and remains visible in Loop Bank management.
- Built-in templates cannot be edited in place.
- Duplicating a built-in creates an editable user loop.
- Saved loop relaunch opens a pre-filled draft.

## Milestone 3: artifact-output runner

Test cases:

- Artifact-output loop writes artifact metadata.
- Artifact-output loop writes artifact file to the artifact directory.
- Project file tree remains unchanged unless a coding write target is explicitly selected.
- Child/subagent failure records `agentFailed`.
- Failed iteration exposes retry without deleting the failed attempt.
- Retrying a failed loop creates a fresh loop run from the failed run's configuration and preserves the failed run.
- User stop records `userStopped`.

## Milestone 4: validation loop

Test cases:

- Passing command stops with `success`.
- Failing command continues to next iteration.
- Max iterations records `maxIterationsReached` or `validationFailedAfterFinalIteration`.
- Missing command records `validationUnavailable`.
- Validation output is capped in state and full output is stored as artifact when needed.

## Milestone 5: worktree loop

Test cases:

- Worktree path is generated and can be revealed from the loop card while available.
- Worktree is created before agent work.
- Validation runs in worktree working directory.
- Current checkout remains unchanged.
- Final details include changed files where available.
- Unsafe worktree setup records `unsafeWriteTarget` or `toolFailed`.
- Apply Worktree refuses dirty parent repositories; Discard Worktree requires confirmation; applied/discarded worktrees hide stale worktree actions.

## Milestone 6: maker/checker

Test cases:

- Maker child/subagent run completes before checker child/subagent run starts.
- Checker receives maker child-run summary/artifacts.
- Checker approval stops successfully.
- Checker rejection triggers another maker iteration.
- Checker ask-human result pauses/stops with `humanInputRequired`.
- Checker defaults to report-only.

## UI checks

For every loop UI:

- availability/assignment is shown with text and icon,
- write target is visible before launch,
- destructive/current-checkout choices are clearly labeled,
- running, success, warning, and failure states include text and icon,
- keyboard navigation still works in the slash browser and modal.

## Manual validation commands

On macOS with Xcode available, run focused build/test checks after implementation slices:

```bash
xcodebuild -project agent-deck.xcodeproj -scheme agent-deck -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

```bash
xcodebuild -project agent-deck.xcodeproj -scheme agent-deck -destination 'platform=macOS' test
```

In non-macOS environments, document that Xcode validation could not be run and run any available pure Swift/package or static checks that apply.
