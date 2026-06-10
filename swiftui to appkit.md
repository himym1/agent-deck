# SwiftUI to AppKit transcript unification

## Goal
Collapse the duplicate SwiftUI transcript renderers into the native AppKit ones
so there is exactly one production path per row kind. Today two renderers exist
for most rows; whichever you edit, the user sees the other. This plan removes
the duplication in five stages, smallest blast radius first.

## Current state
Production renders through `PiAgentTranscriptNative*` (NSTableView coordinator +
native row views). The SwiftUI `PiAgentTranscriptCard` still ships because:
1. **Subagent transcripts** (`PiAgentSubagentViews.swift`) render through it.
2. The **earlier-transcript sheet** (archived sessions) renders through it.
3. `NativeBubblePreviewDebug.swift` previews use it (non-production).

The four SwiftUI tool-group views (web, diff summary, inline diff card, compact
preview) are also duplicated by `PiAgentTranscriptNativeToolGroup` and produce
the production diff/web cards. Memory note "live transcript is native, not
SwiftUI childView" is the current rule.

## Duplicated renderers (the cleanup target)

| Row kind | Native (production) | SwiftUI (still alive) |
|---|---|---|
| Assistant message | `PiAgentNativeBubbleView` | `PiAgentTranscriptCard` (.assistant) |
| User question | `PiAgentNativeQuestionView` | `PiAgentTranscriptCard` (.user) + `PiAgentUserMessageContent` |
| Thinking | `PiAgentNativeBubbleView` role=.thinking | `PiAgentTranscriptCard` (.thinking) |
| Tool group, web/diff | `PiAgentNativeToolGroupView.buildWebCard()` / `buildDiffCard()` | `PiAgentWebActivitySummaryView` + `PiAgentThreadDiffSummaryView` + `PiAgentInlineDiffCard` + `PiAgentCompactDiffPreview` |
| Memory recalled | `PiAgentNativeMemoryCardView` | `PiAgentMemoryActivityCard` |
| Status row | `PiAgentNativeStatusRowView` | `PiAgentStatusTranscriptRow` |
| Error / stderr | `PiAgentNativeErrorRowView` | `PiAgentStatusTranscriptRow` (error branch) |
| Retry row | `PiAgentNativeRetryRowView` | `PiAgentRetryCard` |
| Compaction divider | `PiAgentNativeStatusDividerView` | `PiAgentStatusTranscriptRow.compactionDivider` |
| Supervisor request | `PiAgentNativeSupervisorCardView` | `PiSubagentSupervisorRequestCard` |
| Fork origin | `PiAgentNativeForkOriginCardView` | `PiAgentForkOriginCard` |

## Kept as SwiftUI (out of scope)
- `PiAgentCurrentPlanCard`. Interactive, not in scroll list, no perf risk.
- `PiAgentToolTranscriptView`. Only inside the activity-detail popover (modal).

## Stage 1: simplify the earlier-transcript sheet (1/2 day)
**Premise:** archived/earlier transcripts are read-only and not perf-critical.
Routing them through the native dispatcher is overkill; a plain text dump is
enough.

- Locate the earlier-transcript sheet (search "Earlier Transcript" / archived
  sessions reader).
- Replace its body with a simple, copyable `Text`/`TextEditor` dump grouped by
  role, or a minimal native row mount if you want fidelity.
- Once nothing else reads through the SwiftUI status/error/retry/fork/supervisor
  paths, those files are deletable.

**Deletes after this stage**
- `PiAgentRetryCard` (SwiftUI)
- `PiAgentForkOriginCard` (SwiftUI)
- `PiSubagentSupervisorRequestCard` (SwiftUI)
- `PiAgentMemoryActivityCard` (SwiftUI)
- The `.status` / `.error` branches of `PiAgentStatusTranscriptRow` if no callers remain
- The `.thinking`, `.assistant`, `.error`, `.status` branches of
  `PiAgentTranscriptCard.content` (keep the shell while subagent still uses it).

**Risk:** low. Sheet is a fallback view; visual regression on archived sessions only.

## Stage 2: tool-group SwiftUI cleanup (1/2 day)
**Premise:** the native tool-group builder is already production. The SwiftUI
versions exist only for the SwiftUI-side `PiAgentTranscriptCard` thread card,
which the earlier-transcript sheet uses.

Stage 1 removes that consumer; once gone, delete:
- `PiAgentThreadDiffSummaryView`
- `PiAgentInlineDiffCard`
- `PiAgentCompactDiffPreview`
- `PiAgentWebActivitySummaryView`

Keep the data model `PiAgentThreadDiffSummaryView.Row` (move it to a separate
file like `PiAgentThreadDiffSummary.swift`) since the native builder reads it.

**Risk:** low (after Stage 1).

## Stage 3: header symbol convention sweep (1/4 day, can be parallel)
While we're here, normalize chat-card header SF symbols to use `imageScale` +
`fontWeight` instead of `.font(.system(size:))` / `.font(AppTheme.Font.*)`. The
inconsistency was already partially fixed in this branch (Changes/Web/status row
headers). Remaining offenders:
- `PiAgentTranscriptViews.swift:891` fork-branch glyph in question card chrome
- `PiAgentTranscriptViews.swift:2277` steering header (uses `.title3`)
- `PiAgentTranscriptViews.swift:2336` prompt-audit popover header (uses `.title3`)
- `PiAgentTranscriptViews.swift:3194` "Preview not available" placeholder (uses `.title2`)

Native side uses `NativeTranscriptFont.headerIcon` with explicit pointSize. That
is consistent across all native cards, so leave it.

## Stage 4: subagent transcript native port (the real refactor, 2–3 days)

This is the load-bearing one. Today `PiAgentSubagentViews` renders subagent
threads with `PiAgentTranscriptCard`. The residual-scroll-hang memory points at
exactly this surface (`PiNativeSubagentRunCard` is half-native, half-SwiftUI).

Work:
1. Inventory what the subagent thread renders that's distinct from the parent
   transcript (any subagent-only row kinds? Probably none).
2. Build a parallel native dispatcher: re-use `nativeReplyPayload(for:)` for
   the message rows; re-use tool-group / status / error / retry native builders
   for the rest.
3. Replace `PiAgentTranscriptCard(entry: …)` in `PiAgentSubagentViews.swift`
   with mounts to the same NSTableView coordinator pattern the parent uses.
4. Replace SwiftUI hosts inside `PiNativeSubagentRunCard` with native rows.
5. Verify scroll under a subagent-heavy session (the original reason this matters
   for perf).

**Risk:** higher. New coordinator wiring, child-of-card lifecycle, height-cache
matching the parent. Stage this in a feature branch and test against the same
subagent sessions that triggered the residual scroll hang.

## Stage 5: delete `PiAgentTranscriptCard` (last mile, 1/2 day)
After Stage 4, the only remaining consumer of `PiAgentTranscriptCard` is
`NativeBubblePreviewDebug.swift` (debug). Decision:
- **Option A:** rewrite the debug preview to mount the native renderer.
- **Option B:** keep a minimal preview-only SwiftUI shell, no production code.

Then delete:
- `PiAgentTranscriptCard`
- `PiAgentUserMessageContent` (or move its attachment parser into a shared
  model used by `NativeQuestionPayload.make()`)
- The remaining `PiAgentStatusTranscriptRow` if no longer reached

## What stays out
- `PiAgentCurrentPlanCard` — interactive, low-traffic, leave as SwiftUI.
- `PiAgentToolTranscriptView` — modal popover, no perf cost.
- Native `NativeTranscriptFont.headerIcon` — internally consistent across native cards.

## Parity locks (do not change without updating both sides)
- `NativeTranscriptFont.*Size` mirror `AppTheme.Font.*Size`. If you change a
  point size in AppTheme, the native side picks it up via these constants.
- `PiAgentBubbleWidth` (`replyCap`, `huggedUser`) is shared by both renderers.
- `AppTheme.roleUser/.roleThinking/.roleTool/.roleError` + the role opacity
  scales (`roleFillOpacity`, `roleFillStrongOpacity`, `roleStrokeOpacity`) must
  match between SwiftUI Color use and `AppTheme.ns(...)` NSColor bridging.

## Sequencing recommendation
Ship Stages 1+2+3 first (~1 day total). That eliminates ~80% of the "edited
wrong renderer" pain. Stage 4 is a real refactor and should land separately
with a perf rerun on subagent-heavy sessions.
