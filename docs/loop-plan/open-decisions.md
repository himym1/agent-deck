# Loops Open Decisions

## Product decisions

### Should old Chains receive migration support?

Recommendation: no migration unless real user data exists. Chains were unreleased, so the likely best path is removal or a one-release diagnostic warning for `.chain.md` files.

### What does project assignment mean for loops?

Recommendation: assignment controls visibility/availability in `/loops` for that project. Unlike skills, loops are not automatically injected into Pi runtime.

### Should global loops be visible in every project?

Recommendation: yes. Project loops add project-specific options; global loops remain generally available.

### Should built-in loops be editable through overrides?

Recommendation: no for the first release. Users should duplicate or save a customized copy.

### Should loops be file-backed resources?

Recommendation: yes for definitions, no for runs. Definitions are portable; runs are app-managed history.

### Markdown or JSON definitions?

Recommendation: `.loop.md` with frontmatter for definitions; JSON for run state.

## Execution decisions

### Can Pi start loops through a tool call?

Recommendation for first release: no. Pi may suggest a loop, but the user should confirm launch through the modal.

### Can loops run in the background or on a schedule?

Recommendation for first release: no. Manual launch only.

### Can loops resume after app restart?

Recommendation for first release: completed history persists; active runs interrupted by quit are marked interrupted. Manual resume can come later.

### Can coding loops write directly to the current checkout?

Recommendation: yes only as an explicit advanced choice with a visible path and confirmation. Default to worktree.

### Should parallel agents ship early?

Recommendation: no. Build single-agent, report-only, validation, and worktree foundations first.

## UI decisions

### Should loop structures be visible to users?

Recommendation: yes. Structure changes cost, risk, and behavior.

### Should disabled future structures be shown?

Recommendation: no. Show only supported structures to avoid promising unfinished behavior.

### Should Save Loop be available before launch or only after completion?

Recommendation: both. Users can save configured loops before launch and useful unsaved runs after completion.

### What should unsaved loops be called?

Recommendation: `Unsaved Loop`.

## Technical decisions

### Where should loop definitions live?

Candidate paths:

```text
~/.pi/agent/loops/<name>.loop.md
<project>/.pi/loops/<name>.loop.md
```

Confirm this against existing resource layout before implementation.

### Where should run state live?

Candidate path:

```text
Application Support/Pilot/LoopRuns/<session-id>/<loop-run-id>/
```

Confirm this against `PiAgentSessionStore` and existing artifact storage.

### Should loop execution be owned by AppViewModel or a separate service?

Recommendation: AppViewModel should coordinate UI state, but execution should live in `LoopRunnerService` and related services.

### Should loop validation command output be stored fully?

Recommendation: store capped output in run state and full output as an artifact when necessary.
