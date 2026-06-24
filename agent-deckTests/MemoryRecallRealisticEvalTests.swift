import XCTest
@testable import agent_deck

/// End-to-end recall + duplicate-guard eval against a REAL workload.
///
/// Unlike `MemoryRecallCalibrationTests` (which re-implements the scoring math to
/// compare strategies), this suite drives the production `AgentMemoryStore` API —
/// `retrieve` and `findNearDuplicate` — against:
///
///  - a corpus replicated from the actual Agent Deck project memory store as of
///    June 2026 (including the two real duplicate pairs that motivated the guard);
///  - queries taken from real session opening prompts (including the messy ones:
///    greetings, screenshot-only asks, off-project questions) labeled by hand.
///
/// It reports three numbers and pins them with assertions so recall changes are
/// measured, not vibes:
///
///  - hit rate      — queries with a relevant memory where one was injected
///  - precision     — fraction of everything injected that was actually relevant
///  - abstain rate  — queries with no relevant memory where nothing was injected
///
/// Skips when the on-device embedding model is unavailable (offline CI).
@MainActor
final class MemoryRecallRealisticEvalTests: XCTestCase {

    private var report: [String] = []
    private func emit(_ s: String) { report.append(s); print(s) }

    // MARK: Corpus — replicated from the real store (titles/summaries/bodies)

    private struct RealMemo {
        let key: String
        let kind: AgentMemoryKind
        let title: String
        let summary: String
        let body: String
        let tags: [String]
    }

    private static let corpus: [RealMemo] = [
        RealMemo(key: "agentsmd", kind: .context,
                 title: "Agent guidance lives in AGENTS.md and docs/agent-guidelines",
                 summary: "Repo-wide coding-agent instructions are now rooted at AGENTS.md, with detailed contributor guidance under docs/agent-guidelines/.",
                 body: "Root instructions for coding agents live in AGENTS.md. Detailed project guidance moved under docs/agent-guidelines/. Current guide set includes INVARIANTS.md, ARCHITECTURE.md, SWIFTUI.md, TESTING.md, RELEASE.md, plus supporting UI docs such as LIQUID-GLASS.md and toolbar-guidelines.md.",
                 tags: ["docs", "agents"]),
        RealMemo(key: "scrollanchor", kind: .context,
                 title: "Pi Agent transcript scroll anchoring during active user scroll",
                 summary: "Pi Agent's NSTableView-backed transcript must not restore absolute scroll anchors while the user is actively or recently scrolling.",
                 body: "In PiAgentViews.swift, PiAgentAppKitTranscriptView.Coordinator.noteHeightsChanged(forIDs:) anchoring model: row-height corrections preserve the top-visible anchor only when the transcript is not pinned to bottom and isUserScrollingRecently == false. During live wheel or trackpad scroll, the user's scroll delta is authoritative; applying an anchor captured before the latest input can fight the gesture and make the streaming assistant row jump.",
                 tags: ["transcript", "scrolling"]),
        RealMemo(key: "emptystate", kind: .context,
                 title: "Shared AppEmptyState component",
                 summary: "Page-level empty states should use AppEmptyState from DesignSystem.swift for consistent ContentUnavailableView framing and padding.",
                 body: "Added AppEmptyState in agent-deck/DesignSystem.swift as the shared design-system wrapper around ContentUnavailableView. Use layout fill for full-pane placeholders (e.g. empty Pi Agent sessions/search results) and default compact for inline/section placeholders.",
                 tags: ["design-system", "empty-state"]),
        RealMemo(key: "sparse", kind: .context,
                 title: "Imported skill removal reconciles sparse checkout",
                 summary: "Removing a Git-imported skill now updates the repository sparse-checkout patterns to match remaining synced skills.",
                 body: "In AppViewModel.swift, unlistSkillFromSyncedRepository(_:) updates ImportedSkillRepository.syncedSkillRelativePaths and then calls reconcileSparseCheckout(for:) for remaining skills, so Git's sparse patterns stop including the removed skill. If no synced skills remain, the repo is unregistered and the app-managed clone is deleted.",
                 tags: ["skills", "git"]),
        RealMemo(key: "nstextview", kind: .context,
                 title: "Pi Agent composer uses AppKit NSTextView",
                 summary: "Pi Agent's composer is backed by a custom DropSafeNSTextView, so standard AppKit text input features such as macOS Dictation can target it.",
                 body: "PiAgentComposerViews.swift defines PiAgentDropSafeTextEditor as an NSViewRepresentable that creates a custom DropSafeNSTextView subclass of NSTextView. Because the composer is an AppKit text view rather than a purely custom text input renderer, system text-input behaviors (typing, paste, dictation insertion) can operate through the normal first-responder chain.",
                 tags: ["composer", "appkit"]),
        RealMemo(key: "dictbutton", kind: .context,
                 title: "Pi Agent composer Dictation button",
                 summary: "Pi Agent composer has a mic button that starts macOS system Dictation through AppKit's responder-chain startDictation: action.",
                 body: "PiAgentComposerViews.swift wires a mic button in PiAgentComposerBox.composerActionControls to increment dictationRequest, which is passed into PiAgentDropSafeTextEditor. The NSViewRepresentable focuses its backing DropSafeNSTextView and calls NSApp.sendAction startDictation. If the responder-chain action is unavailable, the composer shows a message to enable Dictation in System Settings.",
                 tags: ["composer", "dictation"]),
        RealMemo(key: "delegation", kind: .context,
                 title: "Subagent delegation policy setting",
                 summary: "Agent Deck has a global NativeSubagentDelegationPolicy setting that changes parent Pi orchestration guidance for subagents.",
                 body: "Implemented in AppSettings.swift as NativeSubagentDelegationPolicy with light, balanced (default), and strict. Settings > Agent shows the default subagents toggle plus a segmented Delegation policy picker. AppViewModel.nativeSubagentCatalog(for:) injects policy-specific orchestration lines into the parent Pi append-system-prompt.",
                 tags: ["subagents", "settings"]),
        RealMemo(key: "dictshortcut", kind: .context,
                 title: "Pi Agent composer Dictation shortcut",
                 summary: "Pi Agent composer starts macOS system Dictation from the focused text editor with Option-D; there is no visible mic button.",
                 body: "PiAgentComposerViews.swift handles Dictation in the composer's DropSafeNSTextView.keyDown(with:): when the focused editor receives Option-D, the coordinator focuses the text view and calls the responder-chain startDictation action. If unavailable, the composer shows a message to enable Dictation in System Settings. There is intentionally no visible composer mic button.",
                 tags: ["composer", "dictation"]),
        RealMemo(key: "skillwarn", kind: .context,
                 title: "Missing skill warning resolution UX",
                 summary: "Missing skill warnings now explain project-scope mismatches and can copy an existing same-named skill into the global skill catalog.",
                 body: "Updated SkillManagementViews.swift and AppViewModel.swift: missing skill warning details look for a same-named skill visible elsewhere, show its path as Found Elsewhere, explain that the target project cannot resolve it at runtime, and offer Copy to Global Skills. The action copies the skill folder to ~/.pi/agent/skills/<name> and refreshes all project scans.",
                 tags: ["skills", "warnings"]),
        RealMemo(key: "skillwarnmove", kind: .context,
                 title: "Missing skill warning resolution UX moves to global",
                 summary: "Missing skill warnings can now move an existing same-named skill into the global skill catalog.",
                 body: "In SkillManagementViews.swift and AppViewModel.swift, missing skill warning details look for a same-named skill visible elsewhere, show its Found Elsewhere path, explain the project-scope mismatch, and offer Move to Global Skills. The action calls moveSkillToGlobalCatalog(_:), which moves the skill folder to ~/.pi/agent/skills/<name> and refreshes all project scans.",
                 tags: ["skills", "warnings"]),
        RealMemo(key: "memtoggle", kind: .context,
                 title: "Memory toggle lives in Memory view only",
                 summary: "Agent memory is enabled by default for fresh settings and the Pi composer footer no longer exposes a duplicate memory on/off chip.",
                 body: "Updated AppSettings.agentMemoryEnabled default and decode fallback to true. The main memory toggle is in AgentMemoryViews.swift / Memory sidebar. PiAgentRuntimeFooter in PiAgentComposerViews.swift should not show or toggle memory status; the footer now focuses on runtime metrics and session-scoped toggles.",
                 tags: ["memory", "settings"]),
    ]

    // MARK: Queries — real opening prompts, hand-labeled

    private struct EvalQuery {
        let text: String
        /// Keys of memories that count as relevant; empty means recall must abstain.
        let relevant: Set<String>
    }

    private static let evalQueries: [EvalQuery] = [
        // ---- should recall ----
        EvalQuery(text: "how do I start dictation in the composer, is there a mic button?",
                  relevant: ["dictshortcut", "dictbutton"]),
        EvalQuery(text: "my skill isn't showing up in this project",
                  relevant: ["skillwarn", "skillwarnmove"]),
        EvalQuery(text: "can you please remove from the footer of the composer the memory on/off switch? we already have a dedicated memory view. also memory should be on by default in all projects, I guess this is already the case?",
                  relevant: ["memtoggle"]),
        EvalQuery(text: "add an empty placeholder state to the new screen when there are no results",
                  relevant: ["emptystate"]),
        EvalQuery(text: "when the assistant is streaming and I scroll up the transcript jumps back down, the scroll position keeps fighting me",
                  relevant: ["scrollanchor"]),
        EvalQuery(text: "where do the coding agent instructions for this repo live, which file should I update with contributor guidance?",
                  relevant: ["agentsmd"]),
        EvalQuery(text: "removing an imported skill from a synced repository should stop it from syncing, how does that work with git?",
                  relevant: ["sparse"]),
        EvalQuery(text: "is there a setting that controls how aggressively the parent delegates work to subagents?",
                  relevant: ["delegation"]),
        // ---- should abstain (real prompts with no covering memory) ----
        EvalQuery(text: "hello", relevant: []),
        EvalQuery(text: "hello man", relevant: []),
        EvalQuery(text: "write a long pome", relevant: []),
        EvalQuery(text: "can you fix this warning: 'nonisolated(unsafe)' is unnecessary for a constant with 'Sendable' type 'URL?', consider removing it",
                  relevant: []),
        EvalQuery(text: "why the checkboxes are black (the checkmark?)", relevant: []),
        EvalQuery(text: "is the symbol of paperplane same size of the +? in the pi coding agent view sidebar?", relevant: []),
        EvalQuery(text: "I need to you to help me understand where we are with Pidgeon in terms of ASO. I saw impressions going down over time and I still haven't figured out what real keywords and queries drive traffic to my competitors",
                  relevant: []),
        EvalQuery(text: "the alignment of the model text in the subagent card in pi agent view is not vertically centered, you can see it right?",
                  relevant: []),
        EvalQuery(text: "this layout of the viewability popover in the pi agent view needs to be improved, having a check + symbol next to it is misleading. how do you suggest improving it?",
                  relevant: []),
        EvalQuery(text: "Write a long, detailed explanation of how SwiftUI's rendering and diffing works, step by step.",
                  relevant: []),
        // ---- held-out round: added after threshold tuning, never tuned against ----
        EvalQuery(text: "what's the keyboard shortcut to dictate into the composer?",
                  relevant: ["dictshortcut", "dictbutton"]),
        EvalQuery(text: "the chat log keeps snapping back while I read older messages during streaming",
                  relevant: ["scrollanchor"]),
        EvalQuery(text: "which doc do I read before contributing code to this repo?",
                  relevant: ["agentsmd"]),
        EvalQuery(text: "There is something that I'd like you to figure out, basically very often it happens that in pi agent view, whilst a session is running, it goes into IDLE mode (so the session doesn't look active, and basically it looks like it's finished but it's not.",
                  relevant: []),
        EvalQuery(text: "in agent view, that toolbar button that shows open disable reveal, should actually be a right click on the list of agents type. check how we do right click in sessions list and implement it in that way",
                  relevant: []),
        EvalQuery(text: "can you simply take a file and add/edit a comment (just one word) ? as a test... find it yourself",
                  relevant: []),
    ]

    // MARK: Helpers

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-memory-eval", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Populates a fresh store with `memos` and returns record-id → corpus key.
    private func populate(_ store: AgentMemoryStore, memos: [RealMemo], projectPath: String) throws -> [String: String] {
        var keysByID: [String: String] = [:]
        for memo in memos {
            let record = try store.createMemory(
                kind: memo.kind, status: .active,
                title: memo.title, summary: memo.summary, body: memo.body,
                projectPath: projectPath, tags: memo.tags
            )
            keysByID[record.id] = memo.key
        }
        return keysByID
    }

    private func ensureEmbedderReady() async throws {
        guard case .ready = await AgentMemoryEmbedder.shared.ensureReady() else {
            throw XCTSkip("On-device embedding model unavailable")
        }
    }

    // MARK: Recall eval

    func testRealisticRecallPrecision() async throws {
        defer { try? report.joined(separator: "\n").write(toFile: "/tmp/recall_realistic_eval.txt", atomically: true, encoding: .utf8) }
        try await ensureEmbedderReady()
        let projectPath = "/tmp/agent-deck-eval"
        let store = AgentMemoryStore(rootURL: try temporaryDirectory())
        let keysByID = try populate(store, memos: Self.corpus, projectPath: projectPath)

        var hitQueries = 0, hitQueriesRecalled = 0
        var abstainQueries = 0, abstainQueriesCorrect = 0
        var injectedTotal = 0, injectedRelevant = 0

        emit("\n================ REALISTIC RECALL EVAL ================")
        emit("corpus: \(Self.corpus.count) memories (real store replica); queries: \(Self.evalQueries.count) real prompts\n")

        for query in Self.evalQueries {
            let retrieval = await store.retrieve(projectPath: projectPath, query: query.text)
            let injectedKeys = (retrieval?.records ?? []).compactMap { keysByID[$0.id] }
            let isAbstainCase = query.relevant.isEmpty
            if isAbstainCase {
                abstainQueries += 1
                if injectedKeys.isEmpty { abstainQueriesCorrect += 1 }
            } else {
                hitQueries += 1
                if injectedKeys.contains(where: { query.relevant.contains($0) }) { hitQueriesRecalled += 1 }
            }
            injectedTotal += injectedKeys.count
            injectedRelevant += injectedKeys.filter { query.relevant.contains($0) }.count
            let want = isAbstainCase ? "abstain" : query.relevant.sorted().joined(separator: "|")
            let got = injectedKeys.isEmpty ? "abstain" : injectedKeys.joined(separator: ", ")
            let ok = isAbstainCase ? injectedKeys.isEmpty : injectedKeys.contains(where: { query.relevant.contains($0) })
            emit("\(ok ? "PASS" : "MISS")  want=[\(want)]  got=[\(got)]  \"\(query.text.prefix(80))\"")
            if !ok, let breakdown = store.lastScoreBreakdown {
                emit("      scores: \(breakdown)")
            }
        }

        let hitRate = Double(hitQueriesRecalled) / Double(max(hitQueries, 1))
        let abstainRate = Double(abstainQueriesCorrect) / Double(max(abstainQueries, 1))
        let precision = injectedTotal == 0 ? 1.0 : Double(injectedRelevant) / Double(injectedTotal)
        emit("\nhit rate      \(hitQueriesRecalled)/\(hitQueries) = \(String(format: "%.2f", hitRate))")
        emit("abstain rate  \(abstainQueriesCorrect)/\(abstainQueries) = \(String(format: "%.2f", abstainRate))")
        emit("precision     \(injectedRelevant)/\(injectedTotal) = \(String(format: "%.2f", precision))")

        // Pinned floors: measured 1.00/1.00/1.00 on this workload (June 2026,
        // Apple sentence-embedding v5). Floors sit one miss below measurement so a
        // model-asset update doesn't flake the suite, while any real regression
        // (two or more misses on any axis) fails loudly.
        XCTAssertGreaterThanOrEqual(hitRate, 0.85, "recall hit rate regressed")
        XCTAssertGreaterThanOrEqual(abstainRate, 0.85, "abstain accuracy regressed")
        XCTAssertGreaterThanOrEqual(precision, 0.80, "injection precision regressed")
    }

    // MARK: Duplicate-guard eval

    func testDuplicateGuardOnRealDuplicatePairs() async throws {
        defer { try? report.joined(separator: "\n").write(toFile: "/tmp/dup_guard_eval.txt", atomically: true, encoding: .utf8) }
        try await ensureEmbedderReady()
        let projectPath = "/tmp/agent-deck-eval-dup"
        let store = AgentMemoryStore(rootURL: try temporaryDirectory())
        // Store state as it was before each second (duplicate) write happened.
        let existing = Self.corpus.filter { !["dictshortcut", "skillwarnmove"].contains($0.key) }
        let keysByID = try populate(store, memos: existing, projectPath: projectPath)
        _ = keysByID

        // The two real duplicate pairs from the production store: the second write
        // must be flagged against the first.
        let dictshortcut = Self.corpus.first { $0.key == "dictshortcut" }!
        let dupe1 = await store.findNearDuplicate(projectPath: projectPath, title: dictshortcut.title, summary: dictshortcut.summary, body: dictshortcut.body)
        emit("dup1 -> \(dupe1?.title ?? "nil") | \(store.lastScoreBreakdown ?? "")")
        XCTAssertEqual(dupe1?.title, "Pi Agent composer Dictation button",
                       "the June 2026 dictation re-write must be flagged as a duplicate of the existing dictation memory")

        let skillwarnmove = Self.corpus.first { $0.key == "skillwarnmove" }!
        let dupe2 = await store.findNearDuplicate(projectPath: projectPath, title: skillwarnmove.title, summary: skillwarnmove.summary, body: skillwarnmove.body)
        emit("dup2 -> \(dupe2?.title ?? "nil") | \(store.lastScoreBreakdown ?? "")")
        XCTAssertEqual(dupe2?.title, "Missing skill warning resolution UX",
                       "the missing-skill-warning re-write must be flagged as a duplicate")

        // Genuinely new facts must NOT be flagged, even when they share the domain
        // vocabulary of an existing memory.
        let newFact1 = await store.findNearDuplicate(
            projectPath: projectPath,
            title: "Composer attachments are pasted as file markers",
            summary: "Files dropped on the composer become inline file markers that expand to paths at send time.",
            body: "Dropping a file on the composer text view inserts a marker token rendered as a chip; PiAgentPasteMarkerCodec expands markers to absolute paths when building the prompt.")
        emit("newFact1 -> \(newFact1?.title ?? "nil") | \(store.lastScoreBreakdown ?? "")")
        XCTAssertNil(newFact1, "a new composer fact must not be blocked by existing composer memories")

        let newFact2 = await store.findNearDuplicate(
            projectPath: projectPath,
            title: "Session worktrees are cleaned up on launch",
            summary: "Orphaned session worktrees left by crashed runs are removed during app startup.",
            body: "cleanupOrphanedNativeSubagentArtifacts() prunes Session Worktrees entries whose owning session no longer exists.")
        XCTAssertNil(newFact2, "an unrelated new fact must never be flagged as a duplicate")
    }

    // MARK: Upsert + index

    func testUpsertUpdatesInPlaceAndReactivatesStale() async throws {
        let projectPath = "/tmp/agent-deck-eval-upsert"
        let store = AgentMemoryStore(rootURL: try temporaryDirectory())
        let record = try store.createMemory(
            kind: .context, status: .active,
            title: "Pi Agent composer Dictation button",
            summary: "Composer has a mic button for Dictation.",
            body: "There is a mic button.",
            projectPath: projectPath
        )
        store.setStatus(id: record.id, status: .stale)

        try store.updateMemory(
            id: record.id,
            title: "Pi Agent composer Dictation shortcut",
            summary: "Composer starts Dictation with Option-D; no mic button.",
            body: "Option-D starts Dictation. The mic button was removed.",
            tags: ["composer"],
            reactivateIfStale: true
        )
        let updated = try XCTUnwrap(store.records.first { $0.id == record.id })
        XCTAssertEqual(updated.status, .active, "agent upsert of a stale memory must reactivate it")
        XCTAssertEqual(updated.title, "Pi Agent composer Dictation shortcut")
        XCTAssertEqual(store.document(for: updated).body, "Option-D starts Dictation. The mic button was removed.")
        XCTAssertEqual(store.records(projectPath: projectPath).count, 1, "upsert must not create a second record")
    }

    func testMemoryIndexPromptListsInjectableMemoriesAndCaps() throws {
        let projectPath = "/tmp/agent-deck-eval-index"
        let store = AgentMemoryStore(rootURL: try temporaryDirectory())
        XCTAssertNil(store.memoryIndexPrompt(projectPath: projectPath), "empty store has no index")
        XCTAssertNil(store.memoryIndexPrompt(projectPath: nil), "no project, no index")

        var ids: [String] = []
        for i in 0..<6 {
            ids.append(try store.createMemory(
                kind: .context, status: .active,
                title: "Memory number \(i)", summary: "Summary \(i).", body: "Body \(i).",
                projectPath: projectPath
            ).id)
        }
        store.setStatus(id: ids[0], status: .stale)

        let index = try XCTUnwrap(store.memoryIndexPrompt(projectPath: projectPath))
        XCTAssertTrue(index.contains("Project memory index"))
        XCTAssertFalse(index.contains("Memory number 0"), "stale memories stay out of the index")
        for i in 1..<6 { XCTAssertTrue(index.contains("Memory number \(i)")) }

        let capped = try XCTUnwrap(store.memoryIndexPrompt(projectPath: projectPath, maxEntries: 2))
        XCTAssertTrue(capped.contains("…and 3 more"), "overflow is stated, never silently truncated")
        XCTAssertEqual(capped.components(separatedBy: "\n").count, 4, "header + 2 entries + overflow line")
    }

    // MARK: Real loop-dominant corpus (replica of the production agent-deck store)

    /// A replica of the actual agent-deck project memory store as of late June 2026:
    /// 36 active memories where ~28% are loop-themed, so "loop"/"session"/"card"/
    /// "row" dominate the corpus. This is the workload that motivated corpus-IDF
    /// gating + the embedder strong-path term floor: without them, any query
    /// mentioning "loop" flooded recall with the same generic loop cluster. Bodies
    /// are set to the summary (the lexical gate only reads title/summary/tags, so
    /// document frequencies — the thing under test — are identical to production).
    private static let realCorpus: [RealMemo] = [
        RealMemo(key: "agentdeckfreezefix", kind: .context,
                 title: "Agent Deck freeze fixes: prewarm blocklist/settle skip, streaming file-watch gate, async FSEvents, coalesced transcript settle",
                 summary: "Agent Deck UI hangs and hitches from transcript streaming and app activation are mitigated by async FSEvents watch rebuilds, coalesced watched-file refresh, and coalesced transcript scroll-to-bottom layout settles.",
                 body: "Agent Deck UI hangs and hitches from transcript streaming and app activation are mitigated by async FSEvents watch rebuilds, coalesced watched-file refresh, and coalesced transcript scroll-to-bottom layout settles.",
                 tags: ["performance", "hangs", "transcript", "fsevents", "file-watch"]),
        RealMemo(key: "agentdetailviewsta", kind: .context,
                 title: "Agent detail view state loss on project assignment — root cause and fix",
                 summary: "When assigning an agent to a project via the detail view toggle, the view completely refreshes and loses all local @State because EffectiveAgentRecord.id changes and reconcileSnapshotsFromPreferences did not preserve selectedAgentID.",
                 body: "When assigning an agent to a project via the detail view toggle, the view completely refreshes and loses all local @State because EffectiveAgentRecord.id changes and reconcileSnapshotsFromPreferences did not preserve selectedAgentID.",
                 tags: ["agents", "view-state", "selection", "EffectiveAgentRecord", "id-stability", "bug"]),
        RealMemo(key: "agentsskillsprompt", kind: .context,
                 title: "Agents/Skills/Prompts/MCP resource views are global; dimming means unassigned nowhere",
                 summary: "Agents, Skills, Prompts, and MCP management views use global resource-list semantics: rows dim only when the resource is neither All Projects/default nor assigned to any project.",
                 body: "Agents, Skills, Prompts, and MCP management views use global resource-list semantics: rows dim only when the resource is neither All Projects/default nor assigned to any project.",
                 tags: ["agents", "skills", "prompts", "mcp", "ui", "dimming"]),
        RealMemo(key: "askusersessionlist", kind: .context,
                 title: "Ask User session list badge should mirror bell attention styling with different symbol",
                 summary: "Ask User waiting state in session lists should use the same badge approach as the requires-attention bell, but with a distinct Ask User symbol.",
                 body: "Ask User waiting state in session lists should use the same badge approach as the requires-attention bell, but with a distinct Ask User symbol.",
                 tags: ["ask-user", "session-list", "ui", "badge"]),
        RealMemo(key: "autonomousoffscree", kind: .context,
                 title: "Autonomous offscreen perf harness + perf-fix loop for Agent Deck",
                 summary: "Agent Deck Perf Hunt loop should run AutoPerf without live Agent Deck safety prompts or extra justification text.",
                 body: "Agent Deck Perf Hunt loop should run AutoPerf without live Agent Deck safety prompts or extra justification text.",
                 tags: ["loops", "autoperf", "performance"]),
        RealMemo(key: "builtinloopsaredis", kind: .context,
                 title: "Built-in loops are disabled for now",
                 summary: "When working on Agent Deck Loop Bank after June 23 2026, do not assume bundled built-in loop templates exist; the user asked to wipe the current built-in loops completely for now.",
                 body: "When working on Agent Deck Loop Bank after June 23 2026, do not assume bundled built-in loop templates exist; the user asked to wipe the current built-in loops completely for now.",
                 tags: ["loops", "loop-bank", "builtins"]),
        RealMemo(key: "builtinsubagentpro", kind: .context,
                 title: "Builtin subagent project override must merge global model override",
                 summary: "Builtin subagent model settings can be lost when a project agentOverride shadows a global agentOverride instead of merging fields, and thinking false must mean explicit off.",
                 body: "Builtin subagent model settings can be lost when a project agentOverride shadows a global agentOverride instead of merging fields, and thinking false must mean explicit off.",
                 tags: ["subagents", "models", "thinking", "agent-overrides", "resolver"]),
        RealMemo(key: "chainsremovedcompl", kind: .context,
                 title: "Chains removed completely from Agent Deck",
                 summary: "When working on Agent Deck resources, do not reintroduce Chains, .chain.md handling, managed_chain docs, or chain retirement diagnostics.",
                 body: "When working on Agent Deck resources, do not reintroduce Chains, .chain.md handling, managed_chain docs, or chain retirement diagnostics.",
                 tags: ["chains", "loops", "scanner", "docs"]),
        RealMemo(key: "codexusagelimitbur", kind: .context,
                 title: "Codex usage-limit burst collapsed to one hourglass card; paired Model Error entries dropped",
                 summary: "Pi emits paired (Model Error, Retry) entries per failed attempt; the thread-builder collapses a quota/retry burst into one card via retryInfo.errorPayload matching.",
                 body: "Pi emits paired (Model Error, Retry) entries per failed attempt; the thread-builder collapses a quota/retry burst into one card via retryInfo.errorPayload matching.",
                 tags: ["transcript", "retry-card", "quota-limit", "codex", "thread-builder", "dedup", "native-cards"]),
        RealMemo(key: "composerlongpasted", kind: .context,
                 title: "Composer long paste draft must persist markers not expanded text",
                 summary: "Composer long paste placeholders like [paste #N ...] must be saved in session drafts as marker text plus payloads, not expanded text, or session switching expands huge drafts and hangs.",
                 body: "Composer long paste placeholders like [paste #N ...] must be saved in session drafts as marker text plus payloads, not expanded text, or session switching expands huge drafts and hangs.",
                 tags: ["composer", "paste", "drafts", "performance", "session-switch"]),
        RealMemo(key: "composerslashselec", kind: .context,
                 title: "Composer slash-selection leaks across session switches",
                 summary: "Unsent slash-selected skill in composer persists when switching Pi sessions because composer drafts do not include slashSelection.",
                 body: "Unsent slash-selected skill in composer persists when switching Pi sessions because composer drafts do not include slashSelection.",
                 tags: ["composer", "slash-selection", "skill", "session-switch", "state-leak"]),
        RealMemo(key: "contextmenubuildcl", kind: .context,
                 title: "ContextMenu build closure runs during SwiftUI layout per visible row — no FS calls inside",
                 summary: "SwiftUI .contextMenu builder is re-evaluated during layout for every visible row via accessibility attachment, so filesystem/stat calls inside it stall scrolling.",
                 body: "SwiftUI .contextMenu builder is re-evaluated during layout for every visible row via accessibility attachment, so filesystem/stat calls inside it stall scrolling.",
                 tags: ["performance", "SwiftUI", "contextMenu", "skills", "lstat", "scrolling"]),
        RealMemo(key: "deckagentspickerca", kind: .context,
                 title: "Deck agents picker card rows are project-assigned only; unassigned agents via Add agents only",
                 summary: "New-session Deck agents picker should show only project assigned/default agents as main rows, with unassigned extra agents managed via Add agents.",
                 body: "New-session Deck agents picker should show only project assigned/default agents as main rows, with unassigned extra agents managed via Add agents.",
                 tags: ["agents", "composer", "session-picker", "project-assignment"]),
        RealMemo(key: "expandedsidebaruse", kind: .context,
                 title: "Expanded sidebar uses exact-updatedAt sort + this-run touches + hybrid freeze; keyboard nav on visible rows only",
                 summary: "Expanded/full coding-agent sidebar orders sessions by exact updatedAt desc, keeps day-granular ordering for the collapsed strip, surfaces this-run-touched sessions, freezes visible row order, and navigates keyboard only through visible rows.",
                 body: "Expanded/full coding-agent sidebar orders sessions by exact updatedAt desc, keeps day-granular ordering for the collapsed strip, surfaces this-run-touched sessions, freezes visible row order, and navigates keyboard only through visible rows.",
                 tags: ["coding-agent-sidebar", "session-ordering", "preview", "keyboard-navigation", "PiAgentSessionGrouping", "PiAgentSessionStore", "CodingAgentExpandedPanel"]),
        RealMemo(key: "grillingquestionss", kind: .context,
                 title: "Grilling questions should include assistant recommendation",
                 summary: "When grilling or refining plans with the user, always make clear which option is the most sensible according to the assistant.",
                 body: "When grilling or refining plans with the user, always make clear which option is the most sensible according to the assistant.",
                 tags: ["planning", "questions", "user-preference"]),
        RealMemo(key: "hidecomposersubage", kind: .context,
                 title: "Hide composer subagent picker during loop launch",
                 summary: "When a loop launch flow is active in Agent Deck, hide the normal composer subagent picker because loops use their own configured agents.",
                 body: "When a loop launch flow is active in Agent Deck, hide the normal composer subagent picker because loops use their own configured agents.",
                 tags: ["loops", "composer", "subagents", "ui"]),
        RealMemo(key: "hidescrollindicato", kind: .context,
                 title: "Hide scroll indicators in Agent Deck UI",
                 summary: "Agent Deck project UI should hide scroll view indicators unless explicitly requested otherwise.",
                 body: "Agent Deck project UI should hide scroll view indicators unless explicitly requested otherwise.",
                 tags: ["ui", "scrollview", "style"]),
        RealMemo(key: "loopagentfieldsdef", kind: .context,
                 title: "Loop agent fields default blank and require explicit selection",
                 summary: "When creating Agent Deck loops, agent fields should not auto-fill placeholder agents like Maker; structures that need agents require explicit selection.",
                 body: "When creating Agent Deck loops, agent fields should not auto-fill placeholder agents like Maker; structures that need agents require explicit selection.",
                 tags: ["loops", "loop-bank", "agents"]),
        RealMemo(key: "looplaunchcontexta", kind: .context,
                 title: "Loop launch context arguments field with first-iteration scope default",
                 summary: "When working on Agent Deck loops, launch context/arguments are a generic per-run input field that defaults to first iteration only and can opt into every iteration.",
                 body: "When working on Agent Deck loops, launch context/arguments are a generic per-run input field that defaults to first iteration only and can opt into every iteration.",
                 tags: ["loops", "launch-context", "prompting"]),
        RealMemo(key: "loopsubagenttransc", kind: .context,
                 title: "Loop subagent transcript sheet must observe async transcript loads",
                 summary: "Loop subagent transcript sheets showed only the prompt because they snapshotted cached transcript entries before async persisted transcript loading completed.",
                 body: "Loop subagent transcript sheets showed only the prompt because they snapshotted cached transcript entries before async persisted transcript loading completed.",
                 tags: ["loops", "subagents", "transcript", "ui"]),
        RealMemo(key: "looptranscriptcard", kind: .context,
                 title: "Loop transcript cards removed; loop status bar owns loop controls",
                 summary: "Agent Deck loop runs should not show the top transcript LoopRun card; all loop status/actions live in the persistent composer-area loop status bar.",
                 body: "Agent Deck loop runs should not show the top transcript LoopRun card; all loop status/actions live in the persistent composer-area loop status bar.",
                 tags: ["loops", "ui", "composer", "transcript"]),
        RealMemo(key: "loopplanworkconsid", kind: .context,
                 title: "Loop-plan work considered complete; Desktop analysis cleared",
                 summary: "When asked about Agent Deck loop-plan completion after June 23 2026, treat the loop-plan work as complete by user decision and do not continue the old checklist unless new requirements are given.",
                 body: "When asked about Agent Deck loop-plan completion after June 23 2026, treat the loop-plan work as complete by user decision and do not continue the old checklist unless new requirements are given.",
                 tags: ["loops", "completion", "desktop-analysis"]),
        RealMemo(key: "loopsuseinfinitysy", kind: .context,
                 title: "Loops use infinity symbol in session row status cluster",
                 summary: "Agent Deck loops should use the SF Symbol infinity placed before commit and push icons in the session row lower-right cluster.",
                 body: "Agent Deck loops should use the SF Symbol infinity placed before commit and push icons in the session row lower-right cluster.",
                 tags: ["loops", "ui", "sf-symbol", "session-list"]),
        RealMemo(key: "loopsusesharedshor", kind: .context,
                 title: "Loops use shared short loop-progress.md memory",
                 summary: "Agent Deck loops use a bounded per-run loop-progress.md file injected into every loop child prompt so rounds build on prior attempts without re-injecting large context.",
                 body: "Agent Deck loops use a bounded per-run loop-progress.md file injected into every loop child prompt so rounds build on prior attempts without re-injecting large context.",
                 tags: ["loops", "memory", "progress", "recaps"]),
        RealMemo(key: "nativesubagentagen", kind: .context,
                 title: "Native subagent agent thinking applies when model is default/inherited",
                 summary: "Native subagent frontmatter thinking with default model should override parent thinking when launching child Pi sessions.",
                 body: "Native subagent frontmatter thinking with default model should override parent thinking when launching child Pi sessions.",
                 tags: ["subagents", "model-thinking", "launch-planner"]),
        RealMemo(key: "nativetranscriptro", kind: .context,
                 title: "Native transcript rows need initial settle and question chip height before first paint",
                 summary: "Native user question header/card alignment on first send with attachments is fixed by initial settle plus setting chip row height during configure before first paint.",
                 body: "Native user question header/card alignment on first send with attachments is fixed by initial settle plus setting chip row height during configure before first paint.",
                 tags: ["transcript", "native-rows", "layout", "first-paint", "question-card"]),
        RealMemo(key: "parallelgraphchild", kind: .context,
                 title: "Parallel graph child model fields are copied into summary cards",
                 summary: "Parallel agents cards show the same model/thinking identifier style as single-agent cards by copying child model and thinking into graph child records.",
                 body: "Parallel agents cards show the same model/thinking identifier style as single-agent cards by copying child model and thinking into graph child records.",
                 tags: ["parallel-agents", "model-chip", "subagents", "swiftui"]),
        RealMemo(key: "pibuiltinbasesyste", kind: .context,
                 title: "Pi built-in base system prompt location and Agent Deck preview extraction",
                 summary: "Where Pi's built-in base system prompt lives and how Agent Deck extracts it for the System Prompt preview when no SYSTEM.md exists.",
                 body: "Where Pi's built-in base system prompt lives and how Agent Deck extracts it for the System Prompt preview when no SYSTEM.md exists.",
                 tags: ["system-prompt", "pi", "preview"]),
        RealMemo(key: "pitranscriptcardsc", kind: .context,
                 title: "Pi transcript cards cropped until session switch due stale row heights",
                 summary: "Pi coding-agent transcript cards or bubbles cropped until switching sessions are caused by stale NSTableView row height estimates/caches; fix with narrow debounced visible-row remeasure outside AppKit layout.",
                 body: "Pi coding-agent transcript cards or bubbles cropped until switching sessions are caused by stale NSTableView row height estimates/caches; fix with narrow debounced visible-row remeasure outside AppKit layout.",
                 tags: ["pi-transcript", "layout", "nstableview", "height-cache", "cropping", "performance"]),
        RealMemo(key: "selectionreconcile", kind: .context,
                 title: "Selection reconciler must not coerce by selectedProjectPath after unscoping + delete must select next visible neighbor",
                 summary: "After the PiAgent session list was unscoped to global, the selection reconciler must validate by existence not selectedProjectPath, and post-delete selection uses nextSelectionAfterDeletion from the visible grouped list.",
                 body: "After the PiAgent session list was unscoped to global, the selection reconciler must validate by existence not selectedProjectPath, and post-delete selection uses nextSelectionAfterDeletion from the visible grouped list.",
                 tags: ["pi-agent", "session-selection", "unscoping", "regression"]),
        RealMemo(key: "sessionlistorderin", kind: .context,
                 title: "Session list ordering: expanded sidebar exact sort uses freeze; compact/store keep stable comparator",
                 summary: "Expanded coding-agent sidebar session ordering uses exact updatedAt with a hybrid freeze, while compact/store ordering keep day-granular stability.",
                 body: "Expanded coding-agent sidebar session ordering uses exact updatedAt with a hybrid freeze, while compact/store ordering keep day-granular stability.",
                 tags: ["session-ordering", "coding-agent-sidebar", "swiftui", "anti-jump"]),
        RealMemo(key: "sidebarexpansiontr", kind: .context,
                 title: "Sidebar expansion transcript hangs from offscreen prewarm height measurement",
                 summary: "Sidebar expansion transcript hangs can be caused by PiAgent transcript prewarm forcing offscreen height measurement after width changes.",
                 body: "Sidebar expansion transcript hangs can be caused by PiAgent transcript prewarm forcing offscreen height measurement after width changes.",
                 tags: ["PiAgent", "performance", "sidebar", "transcript", "prewarm"]),
        RealMemo(key: "subagentconsoleout", kind: .context,
                 title: "Subagent console output emitters and AGENTDECK_RPC_LOG flag",
                 summary: "Where Agent Deck subagent runs print to console and what flag controls it.",
                 body: "Where Agent Deck subagent runs print to console and what flag controls it.",
                 tags: ["subagent", "logging", "rpc", "pi-subagent-run-service", "pi-agent-runner-service", "rpc-debug-log", "nslog"]),
        RealMemo(key: "systempromptuishou", kind: .context,
                 title: "System Prompt UI should avoid ambiguous Available labels and ragged inline row status",
                 summary: "For Agent Deck resource rows, avoid ambiguous labels like Available and ragged inline status text next to titles; use meaningful wording and aligned design-system typography.",
                 body: "For Agent Deck resource rows, avoid ambiguous labels like Available and ragged inline status text next to titles; use meaningful wording and aligned design-system typography.",
                 tags: ["ui", "design-system", "system-prompt", "status-labels"]),
        RealMemo(key: "systempromptscreen", kind: .context,
                 title: "System Prompt screen redesigned: master-detail list + inline editor",
                 summary: "System Instructions screen redesigned as a SplitView master-detail (file list + inline editor), always-enabled, shared toolbar project picker.",
                 body: "System Instructions screen redesigned as a SplitView master-detail (file list + inline editor), always-enabled, shared toolbar project picker.",
                 tags: ["system-prompt", "instructions", "refactor", "master-detail", "ui", "toolbar", "splitview"]),
        RealMemo(key: "transcriptcardicon", kind: .context,
                 title: "Transcript card icon + header font canonical spec — retry/error cards aligned",
                 summary: "Pi transcript retry and error cards must use the shared 16pt headerIcon slot and the canonical header font, not bespoke 18pt/14pt or callout/caption fonts.",
                 body: "Pi transcript retry and error cards must use the shared 16pt headerIcon slot and the canonical header font, not bespoke 18pt/14pt or callout/caption fonts.",
                 tags: ["transcript", "native-cards", "swiftui", "design-system", "retry-card", "error-card", "icons", "typography"]),
    ]

    // MARK: Recall eval against the real loop-dominant corpus

    /// Drives the production `retrieve` against the real agent-deck corpus (28%
    /// loop-themed) using the actual opening prompts of 9 production sessions,
    /// hand-labeled. This is the workload that corpus-IDF gating + the strong-path
    /// term floor were tuned against, so it pins the two properties that matter:
    ///
    ///  - real hits survive (parallel-card, infinity-symbol, redundant-loop-card
    ///    each share ≥2 discriminative terms and must still be injected), and
    ///  - the loop flood is excluded on noise prompts whose discriminative overlap
    ///    with the generic loop cluster is zero (embedder-independent).
    ///
    /// Skips when the on-device embedding model is unavailable (offline CI).
    func testRealLoopDominantSessionRecall() async throws {
        defer { try? report.joined(separator: "\n").write(toFile: "/tmp/recall_real_sessions_eval.txt", atomically: true, encoding: .utf8) }
        try await ensureEmbedderReady()
        let projectPath = "/tmp/agent-deck-real-eval"
        let store = AgentMemoryStore(rootURL: try temporaryDirectory())
        let keysByID = try populate(store, memos: Self.realCorpus, projectPath: projectPath)

        struct SessionQuery {
            let label: String
            let text: String
            /// Corpus keys that count as relevant; empty = recall should abstain.
            let relevant: Set<String>
            /// Corpus keys that must NOT be injected. Chosen to share ZERO
            /// discriminative terms with the prompt, so their exclusion is
            /// embedder-independent (a regression here means gating broke).
            let forbidden: Set<String>
        }

        let queries: [SessionQuery] = [
            SessionQuery(label: "parallel-card-model",
                         text: "in the parallel agents card I do not see the model in the same way I can see it for the single agent. confirm and fix it. use the exact same style",
                         relevant: ["parallelgraphchild"], forbidden: []),
            SessionQuery(label: "infinity-session-row",
                         text: "the infinity symbol that appears in the session list row when a loop is running, can you understand how it works? I saw it but then it disappeared",
                         relevant: ["loopsuseinfinitysy"], forbidden: []),
            SessionQuery(label: "remove-redundant-loop-card",
                         text: "when running a loop that top card is redundant considering we have the bottom bit in the composer, can we remove the card altogether",
                         relevant: ["looptranscriptcard"], forbidden: []),
            SessionQuery(label: "remove-loop-confirmation",
                         text: "in my only loop I want to remove the part in the loop that makes the LLM ask me that confirmation as I run loops from my main app so that's not an issue anymore",
                         relevant: [],
                         forbidden: ["loopplanworkconsid", "builtinloopsaredis", "hidecomposersubage", "loopsuseinfinitysy"]),
            SessionQuery(label: "loops-edit-button",
                         text: "in the loops view edit should be done exactly like in agents view where there is an edit button at the top that opens a sheet, use the exact same logic and style",
                         relevant: [],
                         forbidden: ["loopplanworkconsid", "builtinloopsaredis", "hidecomposersubage"]),
            SessionQuery(label: "chat-steering-logic",
                         text: "can you describe how the steering is currently done for messages sent in the chat UI whilst the LLM is replying? how does the user understand if the steering has been sent or still queued?",
                         relevant: [], forbidden: []),
            SessionQuery(label: "understand-loops-framework",
                         text: "I want you to understand deeply how our loops system and framework works. once ready tell me yes",
                         relevant: [], forbidden: []),
            SessionQuery(label: "minimap-nav-indicator",
                         text: "add a smooth notion/substack-like indicator that animates to select messages sent by the user and scroll to them, so the user understands where it is in the conversation",
                         relevant: [], forbidden: []),
            SessionQuery(label: "clarify-memory-recall",
                         text: "does memory recalled mean the memory gets injected, or just evaluated for it but not necessarily injected?",
                         relevant: [], forbidden: []),
        ]

        var hitQueries = 0, hitRecalled = 0
        var abstainQueries = 0, abstainCorrect = 0
        var injectedTotal = 0, injectedRelevant = 0
        var forbiddenViolations: [String] = []

        emit("\n=========== REAL LOOP-DOMINANT SESSION RECALL ===========")
        emit("corpus: \(Self.realCorpus.count) memories (replica of the real agent-deck store); \(queries.count) real session prompts\n")

        for query in queries {
            let retrieval = await store.retrieve(projectPath: projectPath, query: query.text)
            let keys = (retrieval?.records ?? []).compactMap { keysByID[$0.id] }
            let isHitCase = !query.relevant.isEmpty
            let hit = keys.contains { query.relevant.contains($0) }
            if isHitCase {
                hitQueries += 1
                if hit { hitRecalled += 1 }
            } else {
                abstainQueries += 1
                if keys.isEmpty { abstainCorrect += 1 }
            }
            injectedTotal += keys.count
            injectedRelevant += keys.filter { query.relevant.contains($0) }.count
            let viol = keys.filter { query.forbidden.contains($0) }
            if !viol.isEmpty { forbiddenViolations.append("\(query.label): injected forbidden \(viol)") }
            let want = isHitCase ? query.relevant.sorted().joined(separator: "|") : "abstain"
            let got = keys.isEmpty ? "abstain" : keys.joined(separator: ", ")
            let ok = (isHitCase ? hit : keys.isEmpty) && viol.isEmpty
            emit("\(ok ? "PASS" : "MISS") [\(query.label)] want=[\(want)] got=[\(got)]")
            if !ok, let breakdown = store.lastScoreBreakdown {
                emit("      scores: \(breakdown)")
            }
        }

        let hitRate = Double(hitRecalled) / Double(max(hitQueries, 1))
        let abstainRate = Double(abstainCorrect) / Double(max(abstainQueries, 1))
        let precision = injectedTotal == 0 ? 1.0 : Double(injectedRelevant) / Double(injectedTotal)
        emit("\nhit rate     \(hitRecalled)/\(hitQueries) = \(String(format: "%.2f", hitRate))")
        emit("abstain rate \(abstainCorrect)/\(abstainQueries) = \(String(format: "%.2f", abstainRate))")
        emit("precision    \(injectedRelevant)/\(injectedTotal) = \(String(format: "%.2f", precision))")

        // Embedder-independent: the loop flood must not leak into prompts that share
        // no discriminative term with it. A failure here means the gating regressed.
        XCTAssertTrue(forbiddenViolations.isEmpty,
                      "loop flood leaked into recall: \(forbiddenViolations.joined(separator: "; "))")
        // Real hits must survive the tighter gating (floor leaves room for one
        // embedder-hostile miss without flaking).
        XCTAssertGreaterThanOrEqual(hitRate, 0.66, "real-hit recall regressed")
        // Most noise prompts should now abstain instead of flooding.
        XCTAssertGreaterThanOrEqual(abstainRate, 0.50, "noise abstain rate regressed")
    }
}
