# Loops Testing Plan

## Test strategy

Each milestone should include focused unit tests and at least one integration or smoke test for the end-to-end path it introduces.

Avoid waiting until all loop structures exist before testing. Every vertical slice should be independently shippable or safely hidden.

## Milestone 1: unsaved loop skeleton

Test cases:

- `/loops` category appears in slash universe.
- Create New Loop opens a draft modal.
- Draft requires goal and write target.
- Launch creates a LoopRun.
- A chat rejects a second active loop.
- Loop card renders running and completed states.
- Completed run records a stop reason.

## Milestone 2: Loop Bank

Test cases:

- Save loop globally.
- Save loop to project.
- Global loop appears across project contexts.
- Project loop appears only for that project.
- Built-in templates cannot be edited in place.
- Duplicating a built-in creates an editable user loop.
- Saved loop relaunch opens a pre-filled draft.

## Milestone 3: report-only runner

Test cases:

- Report-only loop writes artifact metadata.
- Report-only loop writes artifact file to the artifact directory.
- Project file tree remains unchanged.
- Agent failure records `agentFailed`.
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

- Worktree path is generated and shown.
- Worktree is created before agent work.
- Validation runs in worktree working directory.
- Current checkout remains unchanged.
- Final diff summary includes changed files.
- Unsafe worktree setup records `unsafeWriteTarget` or `toolFailed`.

## Milestone 6: maker/checker

Test cases:

- Maker runs before checker.
- Checker receives maker summary/artifacts.
- Checker approval stops successfully.
- Checker rejection triggers another maker iteration.
- Checker ask-human result pauses/stops with `humanInputRequired`.
- Checker defaults to report-only.

## UI checks

For every loop UI:

- scope is shown with text and icon,
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
