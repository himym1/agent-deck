# Loops End-to-End Plan

## Purpose

Loops are planned as Agent Deck's composer-launched iterative workflow primitive. A loop can be launched temporarily from the current chat, or saved into the Loop Bank for reuse. Saved loops behave like other managed resources: they may be global or project-scoped, and every launch must make its write target explicit.

This plan intentionally replaces the unreleased user-facing Chains concept. Chain-like sequencing may still exist internally where needed, but the product language and resource model should converge on Loops.

## Product definition

A **Loop** is a bounded agent workflow with:

- a goal,
- a structure,
- one or more agent roles,
- a check policy,
- a stop policy,
- an explicit write target,
- persisted run state,
- visible iteration history,
- and a final stop reason.

A **Loop Definition** is the reusable saved resource.

A **Loop Run** is one execution of a loop in one chat.

A **Loop Draft** is the unsaved configuration edited in the launch modal.

## Core product rules

1. The composer is the primary entry point: `/loops` opens saved loops and Create New Loop.
2. One chat may have only one active loop at a time.
3. Unsaved loops are allowed and should be first-class.
4. Any launched loop can be saved into the Loop Bank after configuration or completion.
5. Saved loops can be global or project-scoped.
6. Built-in loop templates are read-only; users duplicate or save customized copies.
7. Every loop launch shows the write target before execution.
8. Coding loops default to a new worktree.
9. Report-only loops may write artifacts only, never project files.
10. Every loop ends with a stop reason.
11. Loop structures are user-visible, not hidden implementation details.
12. Scheduled/background loops are out of scope for the first release.

## Documentation map

Read these documents in order when implementing the feature:

1. [Product model](product-model.md) — user model, terminology, and loop structures.
2. [End-to-end milestones](milestones.md) — vertical slices for modular implementation.
3. [Architecture plan](architecture.md) — data model, services, persistence, and runtime boundaries.
4. [Composer and UI plan](ui-composer.md) — `/loops`, launch modal, Loop Bank, and transcript cards.
5. [Execution and safety plan](execution-safety.md) — runner behavior, write targets, stop reasons, and validation.
6. [Chains retirement plan](chains-retirement.md) — remove the unreleased Chains product surface.
7. [Testing plan](testing.md) — focused checks by milestone.
8. [Open decisions](open-decisions.md) — decisions to resolve before or during implementation.

## Recommended implementation strategy

Build Loops as vertical slices. Each slice must be usable end-to-end and tested before the next slice extends it.

The first useful slice should not be a generic workflow engine. It should be:

```text
/loops
→ Create New Loop
→ Report Only or Single Agent
→ Launch in current chat
→ Show loop card
→ Complete with stop reason
→ Save to Loop Bank
```

Once that path works, add validation, worktrees, maker/checker, and multi-agent structures on top.
