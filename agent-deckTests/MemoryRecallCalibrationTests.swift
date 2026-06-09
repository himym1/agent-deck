import XCTest
import NaturalLanguage
@testable import agent_deck

/// Calibration + regression harness for embedding-based memory recall.
///
/// Recall scores memories against a query with mean-pooled `NLContextualEmbedding`
/// vectors. Those vectors are anisotropic (every sentence crowds into a narrow cone,
/// so unrelated texts sit near 0.9 cosine), which makes a raw absolute threshold
/// useless. This test loads the REAL on-device model, embeds a labeled fake corpus,
/// and compares three de-biasing strategies so the production thresholds and the
/// centering approach are chosen from data rather than guessed:
///
///   raw      — plain cosine (baseline; expected to barely separate topics)
///   perSet   — subtract the centroid of the memories being ranked (fragile for small
///              corpora: the centroid is a bad estimate and the geometry degenerates)
///   global   — subtract a centroid estimated from a large, fixed background set
///              (anisotropy is a property of the MODEL, not the project, so this is
///              stable regardless of how many memories the project has)
///
/// Skips when the model asset isn't available (offline CI), so it never blocks a build.
final class MemoryRecallCalibrationTests: XCTestCase {

    /// xcodebuild routes test `print` to the .xcresult, not the console, so the report
    /// is also written to `/tmp/recall_calibration.txt` for inspection.
    private var report: [String] = []
    private func emit(_ s: String) { report.append(s); print(s) }

    // MARK: Fake labeled corpus

    private struct Memo {
        let title: String
        let summary: String
        let topic: String
        let body: String
        var text: String { "\(title)\n\(summary)\n\(String(body.prefix(600)))" }
    }

    private struct Query {
        let text: String
        let relevantTopic: String
    }

    private let corpus: [Memo] = [
        Memo(title: "Popover theming uses the glass toolbar background",
             summary: "Composer and toolbar popovers must open on the same themed glass surface as the info and eye-visibility popovers.",
             topic: "theming",
             body: "Popovers opened from the composer (the + button and the send paperplane) were using the default system material instead of the app's themed glass. They should match the toolbar popovers."),
        Memo(title: "Theme tokens drive canvas colors",
             summary: "AppTheme background, surface, and stroke tokens are computed off the active theme and applied to the window and panels.",
             topic: "theming",
             body: "Theme now drives the canvas, not just accents. Neutrals are computed vars off ThemeManager.activeTheme."),
        Memo(title: "Transcript scroll jank from per-row layout",
             summary: "Scrolling back through long sessions hangs because each markdown row re-lays-out in its hosting view on every vend.",
             topic: "transcript",
             body: "Jank is per-vend SwiftUI markdown layout in NSHostingView cells, 15 to 66ms per markdown row. Fix is caching the render product across vends."),
        Memo(title: "Transcript cell cache across vends",
             summary: "The transcript keeps one persistent cell per item id so scroll-back is a no-op configure instead of a rebuild.",
             topic: "transcript",
             body: "Coordinator holds a cellCache keyed by item id; makeView reuse is not enough."),
        Memo(title: "Provider login writes auth.json",
             summary: "Signing in from the Models view writes the agent auth.json; API key is pure Swift, OAuth bridges to node.",
             topic: "auth",
             body: "In-app sign in and out writes the coding agent auth.json. OAuth ids are anthropic, github-copilot, openai-codex."),
        Memo(title: "OAuth bridge to node AuthStorage",
             summary: "OAuth login is handled by a node bridge into AuthStorage.login rather than the Swift RPC path.",
             topic: "auth",
             body: "There is no RPC auth for OAuth; the node bridge performs the login."),
        Memo(title: "Skill catalog visibility warnings",
             summary: "Missing skill warnings explain project-scope mismatches and can move a same-named skill into the global catalog.",
             topic: "skills",
             body: "When a skill is not visible in a project, the warning explains the scope mismatch and offers to copy or move it to the global skill catalog."),
        Memo(title: "Imported skill removal reconciles sparse checkout",
             summary: "Removing a git-imported skill updates the repository sparse-checkout patterns to match the remaining synced skills.",
             topic: "skills",
             body: "Sparse-checkout patterns are rewritten so deleted imported skills stop syncing."),
        Memo(title: "Markdown renders native unless it has images or tables",
             summary: "The markdown view renders natively to avoid WebContent hangs, falling back to a web view only for images, tables, or raw HTML.",
             topic: "markdown",
             body: "Tables and images route to the heavier renderer; everything else is native and incremental."),
        Memo(title: "Composer Dictation starts with Option-D",
             summary: "The composer starts macOS system Dictation from the focused text editor with Option-D; there is no visible mic button.",
             topic: "input",
             body: "On Option-D the coordinator focuses the text view and calls the responder-chain startDictation action. There is intentionally no mic button."),
        Memo(title: "Composer uses AppKit NSTextView",
             summary: "The composer is backed by a custom DropSafeNSTextView so standard AppKit text input features can target it.",
             topic: "input",
             body: "Because the composer is a real NSTextView, system text services such as Dictation work against it."),
        Memo(title: "Sandbox scheme is an isolated fresh-install rehearsal",
             summary: "The debug sandbox scheme uses an isolated support directory and UserDefaults suite and forces onboarding.",
             topic: "sandbox",
             body: "The sandbox scheme simulates a clean machine: separate agent dir, defaults suite, forced onboarding, simulate-no-node."),
        Memo(title: "Subagent delegation policy setting",
             summary: "A global delegation policy setting changes how the parent orchestrates subagents.",
             topic: "subagent",
             body: "The NativeSubagentDelegationPolicy setting adjusts parent guidance for delegating work to deck agents."),
    ]

    private let queries: [Query] = [
        Query(text: "in the coding view the + and paperplane popovers aren't themed like the toolbar popovers", relevantTopic: "theming"),
        Query(text: "scrolling back through a long session hangs and drops frames", relevantTopic: "transcript"),
        Query(text: "how do I sign in to anthropic, the login isn't working", relevantTopic: "auth"),
        Query(text: "my skill isn't showing up in this project", relevantTopic: "skills"),
        Query(text: "tables in markdown render slowly and freeze the view", relevantTopic: "markdown"),
        Query(text: "start dictation in the message box", relevantTopic: "input"),
    ]

    /// Diverse, generic sentences unrelated to the corpus, used to estimate the model's
    /// anisotropy direction for the `global` strategy. Real code would bake an analogous
    /// set (or accumulate one across all memories) and persist its mean.
    private let backgroundSentences: [String] = [
        "The weather turned cold and the rivers froze over by morning.",
        "She bought three apples and a loaf of bread at the market.",
        "Quarterly revenue exceeded expectations across every region.",
        "The orchestra tuned their instruments before the performance began.",
        "A gentle rain fell on the quiet mountain village overnight.",
        "He repaired the old bicycle and rode it to the coast.",
        "The recipe calls for two cups of flour and a pinch of salt.",
        "Astronomers discovered a faint galaxy at the edge of the survey.",
        "The committee postponed the vote until the following week.",
        "Children played in the park while the dogs chased a ball.",
        "The novel explores themes of memory, loss, and reconciliation.",
        "Stock prices fluctuated wildly during the afternoon session.",
        "A new bakery opened on the corner of Fifth and Main.",
        "The hikers reached the summit just before the storm arrived.",
        "Engineers tested the bridge for stress under heavy load.",
        "The museum unveiled a collection of ancient pottery.",
        "Farmers harvested the wheat before the first frost.",
        "The lecture covered the history of the Roman aqueducts.",
        "A flock of geese flew south as the days grew shorter.",
        "The chef garnished the plate with fresh herbs and citrus.",
        "Volunteers cleaned the beach and sorted the recyclables.",
        "The train departed the station exactly on schedule.",
        "Researchers published their findings in a peer-reviewed journal.",
        "The garden bloomed with tulips and daffodils in spring.",
        "A power outage left the neighborhood dark for hours.",
        "The athlete broke the national record at the meet.",
        "Negotiators reached an agreement after months of talks.",
        "The library extended its hours during exam season.",
        "Snow blanketed the city and schools closed for the day.",
        "The startup raised funding to expand into new markets.",
        "Tourists photographed the waterfall from the wooden bridge.",
        "The teacher assigned an essay on coastal erosion.",
        "A violinist performed a solo to a packed concert hall.",
        "The factory automated its assembly line last year.",
        "Birds migrated thousands of miles to warmer climates.",
        "The court adjourned until the following Monday morning.",
        "Bakers prepared loaves of sourdough before dawn.",
        "The expedition mapped an uncharted stretch of the river.",
        "Investors watched the currency markets nervously.",
        "The play received glowing reviews from the local critics.",
    ]

    // MARK: Embedding (mirrors production: mean-pool + L2-normalize)

    private func embed(_ text: String, model: NLContextualEmbedding) -> [Float]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let result = try? model.embeddingResult(for: trimmed, language: .english) else { return nil }
        let dimension = model.dimension
        guard dimension > 0 else { return nil }
        var sum = [Double](repeating: 0, count: dimension)
        var count = 0
        result.enumerateTokenVectors(in: trimmed.startIndex..<trimmed.endIndex) { vector, _ in
            if vector.count == dimension {
                for i in 0..<dimension { sum[i] += Double(vector[i]) }
                count += 1
            }
            return true
        }
        guard count > 0 else { return nil }
        var mean = [Float](repeating: 0, count: dimension)
        var norm = 0.0
        for i in 0..<dimension {
            let value = sum[i] / Double(count)
            norm += value * value
            mean[i] = Float(value)
        }
        norm = norm.squareRoot()
        guard norm > 0 else { return nil }
        let inverse = Float(1.0 / norm)
        for i in 0..<dimension { mean[i] *= inverse }
        return mean
    }

    private func dot(_ a: [Float], _ b: [Float]) -> Float {
        var s: Float = 0
        for i in 0..<min(a.count, b.count) { s += a[i] * b[i] }
        return s
    }

    private func centerNormalize(_ v: [Float], _ centroid: [Float]) -> [Float]? {
        var out = [Float](repeating: 0, count: v.count)
        var norm: Float = 0
        for i in 0..<v.count { let d = v[i] - centroid[i]; out[i] = d; norm += d * d }
        norm = norm.squareRoot()
        guard norm > 0 else { return nil }
        for i in 0..<v.count { out[i] /= norm }
        return out
    }

    private func centroid(_ vectors: [[Float]]) -> [Float] {
        guard let dim = vectors.first?.count, !vectors.isEmpty else { return [] }
        var c = [Float](repeating: 0, count: dim)
        for v in vectors { for i in 0..<dim { c[i] += v[i] } }
        let inv = Float(1.0 / Double(vectors.count))
        for i in 0..<dim { c[i] *= inv }
        return c
    }

    // MARK: Strategies — return score per memory index for one query

    private enum Strategy: String, CaseIterable { case raw, perSet, global }

    private func score(strategy: Strategy, queryVec: [Float], docVecs: [[Float]], backgroundMean: [Float]) -> [Float] {
        switch strategy {
        case .raw:
            return docVecs.map { dot(queryVec, $0) }
        case .perSet:
            guard docVecs.count >= 2 else { return docVecs.map { dot(queryVec, $0) } }
            let c = centroid(docVecs)
            guard let q = centerNormalize(queryVec, c) else { return docVecs.map { _ in 0 } }
            return docVecs.map { centerNormalize($0, c).map { dot(q, $0) } ?? 0 }
        case .global:
            guard let q = centerNormalize(queryVec, backgroundMean) else { return docVecs.map { _ in 0 } }
            return docVecs.map { centerNormalize($0, backgroundMean).map { dot(q, $0) } ?? 0 }
        }
    }

    // MARK: Test

    func testRecallStrategyCalibration() async throws {
        defer { try? report.joined(separator: "\n").write(toFile: "/tmp/recall_calibration.txt", atomically: true, encoding: .utf8) }
        guard let model = NLContextualEmbedding(language: .english) else {
            throw XCTSkip("No English contextual embedding model on this OS")
        }
        if !model.hasAvailableAssets {
            _ = try? await model.requestAssets()
        }
        do { try model.load() } catch { throw XCTSkip("Embedding model asset unavailable: \(error)") }
        defer { model.unload() }

        // Embed everything once.
        let docVecs: [[Float]] = try corpus.map { memo in
            guard let v = embed(memo.text, model: model) else { throw XCTSkip("embed failed") }
            return v
        }
        let backgroundMean = centroid(try backgroundSentences.map {
            guard let v = embed($0, model: model) else { throw XCTSkip("embed failed") }
            return v
        })

        emit("\n================ MEMORY RECALL CALIBRATION ================")
        emit("corpus: \(corpus.count) memories, \(Set(corpus.map(\.topic)).count) topics; background: \(backgroundSentences.count) sentences; dim: \(model.dimension)\n")

        // Aggregate separation stats per strategy over the full corpus.
        var aggregate: [Strategy: (gaps: [Float], top1Hits: Int, relScores: [Float], irrScores: [Float])] = [:]
        for s in Strategy.allCases { aggregate[s] = ([], 0, [], []) }

        for query in queries {
            guard let qv = embed(query.text, model: model) else { continue }
            emit("QUERY: \"\(query.text)\"  (relevant topic: \(query.relevantTopic))")
            for strategy in Strategy.allCases {
                let scores = score(strategy: strategy, queryVec: qv, docVecs: docVecs, backgroundMean: backgroundMean)
                let ranked = zip(corpus, scores).sorted { $0.1 > $1.1 }
                let relScores = zip(corpus, scores).filter { $0.0.topic == query.relevantTopic }.map(\.1)
                let irrScores = zip(corpus, scores).filter { $0.0.topic != query.relevantTopic }.map(\.1)
                let gap = (relScores.min() ?? 0) - (irrScores.max() ?? 0)
                let top1Hit = ranked.first?.0.topic == query.relevantTopic
                aggregate[strategy]!.gaps.append(gap)
                aggregate[strategy]!.top1Hits += top1Hit ? 1 : 0
                aggregate[strategy]!.relScores.append(contentsOf: relScores)
                aggregate[strategy]!.irrScores.append(contentsOf: irrScores)
                let top3 = ranked.prefix(3).map { "\($0.0.topic):\(String(format: "%.3f", $0.1))" }.joined(separator: "  ")
                emit(String(format: "  %-7@  top1=%@  relMin=%.3f  irrMax=%.3f  gap=%+.3f   | %@",
                             strategy.rawValue as NSString, top1Hit ? "Y" : "n",
                             relScores.min() ?? 0, irrScores.max() ?? 0, gap, top3))
            }
            emit("")
        }

        emit("---------------- AGGREGATE (full corpus) ----------------")
        for s in Strategy.allCases {
            let a = aggregate[s]!
            let meanGap = a.gaps.reduce(0, +) / Float(max(a.gaps.count, 1))
            let relMean = a.relScores.reduce(0, +) / Float(max(a.relScores.count, 1))
            let irrMean = a.irrScores.reduce(0, +) / Float(max(a.irrScores.count, 1))
            let irrMax = a.irrScores.max() ?? 0
            let relMin = a.relScores.min() ?? 0
            emit(String(format: "  %-7@ top1 %d/%d  meanGap=%+.3f  rel[min %.3f mean %.3f]  irr[mean %.3f max %.3f]  suggestedFloor~%.3f",
                         s.rawValue as NSString, a.top1Hits, queries.count, meanGap,
                         relMin, relMean, irrMean, irrMax, (relMin + irrMax) / 2))
        }

        // Small-corpus stress: the user's real pain. 3 memories, 1 relevant.
        emit("\n---------------- SMALL CORPUS (3 memories, 1 relevant) ----------------")
        let smallRanked = try smallCorpusProbe(model: model, backgroundMean: backgroundMean,
                                               pick: ["theming", "input", "transcript"], query: queries[0])
        emit("\n---------------- ABSTAIN CASE (3 memories, 0 relevant) ----------------")
        _ = try smallCorpusProbe(model: model, backgroundMean: backgroundMean,
                                 pick: ["auth", "skills", "sandbox"], query: queries[0])

        // Regression assertions pin the SHIPPED design (per-set centering + a
        // scale-relative keep gate), which calibration showed ranks best.
        let perSet = aggregate[.perSet]!
        let raw = aggregate[.raw]!
        // 1. Centering must rank the relevant topic first on every query...
        XCTAssertEqual(perSet.top1Hits, queries.count, "per-set centering should rank the relevant topic first for every query")
        // 2. ...and do so at least as well as raw cosine (which the anisotropy cripples).
        XCTAssertGreaterThanOrEqual(perSet.top1Hits, raw.top1Hits, "centering should not rank worse than raw cosine")
        // 3. The user's exact bug: a popover query against [theming, dictation,
        //    transcript] must rank theming first and the keep gate must drop dictation.
        XCTAssertEqual(smallRanked.first?.topic, "theming", "popover query should rank the theming memory first")
        let keepCutoff = (smallRanked.first?.score ?? 0) * AgentMemoryStore.keepScoreRatio
        let kept = smallRanked.filter { $0.score >= keepCutoff }.map(\.topic)
        XCTAssertEqual(kept, ["theming"], "keep gate should return only the theming memory, dropping the dictation/transcript noise")
    }

    /// Returns the per-set-centered ranking (the shipped strategy) for assertions.
    @discardableResult
    private func smallCorpusProbe(model: NLContextualEmbedding, backgroundMean: [Float], pick topics: [String], query: Query) throws -> [(topic: String, score: Float)] {
        let subset = topics.compactMap { topic in corpus.first { $0.topic == topic } }
        let vecs = try subset.map { memo -> [Float] in
            guard let v = embed(memo.text, model: model) else { throw XCTSkip("embed failed") }
            return v
        }
        guard let qv = embed(query.text, model: model) else { return [] }
        emit("query: \"\(query.text)\"  (want topic: \(query.relevantTopic))")
        var perSetRanked: [(topic: String, score: Float)] = []
        for strategy in Strategy.allCases {
            let scores = score(strategy: strategy, queryVec: qv, docVecs: vecs, backgroundMean: backgroundMean)
            let ranked = zip(subset, scores).map { (topic: $0.0.topic, score: $0.1) }.sorted { $0.score > $1.score }
            if strategy == .perSet { perSetRanked = ranked }
            let line = ranked.map { "\($0.topic):\(String(format: "%.3f", $0.score))" }.joined(separator: "  ")
            emit(String(format: "  %-7@  %@", strategy.rawValue as NSString, line))
        }
        return perSetRanked
    }
}
