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
}
