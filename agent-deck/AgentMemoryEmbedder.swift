import Foundation
import NaturalLanguage

/// Outcome of trying to load the on-device embedding model.
nonisolated enum EmbeddingReadiness: Sendable, Equatable {
    case ready(model: String)
    /// Could not load right now (first-run asset still downloading, or offline) —
    /// transient, so a later call retries.
    case unavailable
    /// The device/OS has no embedding model for the language — permanent, no retry.
    case unsupported
}

/// UI-facing status of the on-device recall model. The model ships with macOS, so
/// the working path is effectively instant; the Memory view only surfaces this when
/// recall can't run (`unavailable`/`unsupported`), since recall is fallback-free and
/// otherwise fails silently.
nonisolated enum AgentMemoryEmbeddingStatus: Sendable, Equatable {
    case unknown
    case ready
    case unavailable
    case unsupported
}

/// One memory's stored embedding, tagged with a content hash so recall can tell a
/// cached vector apart from one whose source text has since changed. Persisted as
/// derived data (a rebuildable cache), never as source of truth.
nonisolated struct MemoryVectorEntry: Codable, Sendable {
    let vector: [Float]
    let hash: String
}

/// The text to embed for one memory, plus the hash of that text. Built on the main
/// actor from in-memory record fields (no disk read) and handed to the embedder.
nonisolated struct EmbeddingInput: Sendable {
    let id: String
    let text: String
    let hash: String
}

/// Result of reconciling + scoring a project's memories against a query: the full
/// refreshed vector set (to persist) and the above-threshold cosine scores by id.
nonisolated struct EmbeddingScoreResult: Sendable {
    let vectors: [String: MemoryVectorEntry]
    let scores: [String: Float]
}

/// On-device semantic embeddings for memory recall, backed by `NLContextualEmbedding`
/// (a BERT-class contextual model, macOS 14+). Fully local: no network at inference,
/// no API cost, nothing leaves the machine. The model asset is downloaded once by the
/// OS the first time it is requested, then shared system-wide.
///
/// An `actor` rather than a lock-wrapped class: it serializes access to the
/// non-Sendable `NLContextualEmbedding` and runs its work off the main actor, so
/// recall never embeds on the UI thread.
actor AgentMemoryEmbedder {
    static let shared = AgentMemoryEmbedder()

    private var model: NLContextualEmbedding?
    /// Set only when the device/OS has no embedding model for the language — a
    /// permanent condition, so retrying is pointless. Transient failures (offline
    /// while the asset downloads) are deliberately NOT permanent: the next call
    /// retries, which is what lets a background prewarm recover once network returns.
    private var unsupported = false
    /// The in-flight load, shared by concurrent callers so a launch-time prewarm and
    /// the first recall don't both kick off the asset download.
    private var loadTask: Task<EmbeddingReadiness, Never>?

    /// Loads (downloading the asset if needed) and reports readiness. Idempotent;
    /// safe to call eagerly in the background (prewarm) and again lazily at recall
    /// time.
    func ensureReady() async -> EmbeddingReadiness {
        if let model { return .ready(model: model.modelIdentifier) }
        if unsupported { return .unsupported }
        if let loadTask { return await loadTask.value }
        let task = Task { await self.performLoad() }
        loadTask = task
        let result = await task.value
        loadTask = nil
        return result
    }

    private func performLoad() async -> EmbeddingReadiness {
        guard let candidate = NLContextualEmbedding(language: .english) else {
            unsupported = true
            return .unsupported
        }
        do {
            if !candidate.hasAvailableAssets {
                _ = try await candidate.requestAssets()
            }
            try candidate.load()
        } catch {
            return .unavailable // transient (e.g. offline); a later call retries
        }
        model = candidate
        return .ready(model: candidate.modelIdentifier)
    }

    /// Reuses cached vectors whose hash still matches, embeds the rest, prunes
    /// vectors for ids no longer present, and scores every vector against the query
    /// by cosine similarity (a plain dot product, since vectors are L2-normalized).
    /// Returns nil only when the query itself cannot be embedded.
    func reconcileAndScore(query: String, inputs: [EmbeddingInput], cached: [String: MemoryVectorEntry], threshold: Float) -> EmbeddingScoreResult? {
        guard let queryVector = embed(query) else { return nil }
        var vectors: [String: MemoryVectorEntry] = [:]
        vectors.reserveCapacity(inputs.count)
        for input in inputs {
            if let existing = cached[input.id], existing.hash == input.hash, existing.vector.count == queryVector.count {
                vectors[input.id] = existing
            } else if let vector = embed(input.text), vector.count == queryVector.count {
                vectors[input.id] = MemoryVectorEntry(vector: vector, hash: input.hash)
            }
        }
        var scores: [String: Float] = [:]
        for (id, entry) in vectors {
            var dot: Float = 0
            let vector = entry.vector
            for i in 0..<vector.count { dot += queryVector[i] * vector[i] }
            if dot >= threshold { scores[id] = dot }
        }
        return EmbeddingScoreResult(vectors: vectors, scores: scores)
    }

    /// Mean-pools the per-token contextual vectors into one sentence vector and
    /// L2-normalizes it, so similarity is a dot product. Returns nil for empty text
    /// or when the model isn't loaded.
    private func embed(_ text: String) -> [Float]? {
        guard let model else { return nil }
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
}
