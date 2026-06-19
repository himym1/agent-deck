import XCTest
@testable import agent_deck

/// `NeuralWattCatalogSync` keeps the `neuralwatt` block of `~/.pi/agent/models.json` in sync with
/// the live `/v1/models` endpoint. These tests pin the merge semantics (create-if-missing,
/// preserve sibling providers, best-effort on fetch failure) and the per-model field derivation
/// (reasoning, compat, omitted maxTokens) using an injected fetch and a temp file — no network.
final class NeuralWattCatalogSyncTests: XCTestCase {

    /// Minimal but real-shaped `/v1/models` payload covering the three interesting cases:
    /// a reasoning+reasoning_effort model (glm-5.2), a plain reasoning model, and a non-reasoning
    /// fast variant. Mirrors NeuralWatt's actual response shape (capabilities/limits/pricing).
    private static let sampleModelsJSON = #"""
    {
      "object": "list",
      "data": [
        {
          "id": "glm-5.2",
          "object": "model",
          "max_model_len": 1048560,
          "metadata": {
            "display_name": "GLM-5.2",
            "capabilities": { "reasoning": true, "reasoning_effort": true, "vision": false, "tools": true, "developer_role": false, "system_role": true },
            "limits": { "max_context_length": 1048560, "max_output_tokens": null },
            "pricing": { "input_per_million": 1.45, "output_per_million": 4.5, "cached_input_per_million": 0.3625 }
          }
        },
        {
          "id": "kimi-k2.6",
          "object": "model",
          "max_model_len": 262128,
          "metadata": {
            "display_name": "Kimi K2.6",
            "capabilities": { "reasoning": true, "reasoning_effort": false, "vision": true, "tools": true, "developer_role": false, "system_role": true },
            "limits": { "max_context_length": 262128, "max_output_tokens": null },
            "pricing": { "input_per_million": 0.69, "output_per_million": 3.22, "cached_input_per_million": 0.1725 }
          }
        },
        {
          "id": "kimi-k2.6-fast",
          "object": "model",
          "max_model_len": 262128,
          "metadata": {
            "display_name": "Kimi K2.6 Fast",
            "capabilities": { "reasoning": false, "reasoning_effort": false, "vision": true, "tools": true, "developer_role": false, "system_role": true },
            "limits": { "max_context_length": 262128, "max_output_tokens": null },
            "pricing": { "input_per_million": 0.69, "output_per_million": 3.22, "cached_input_per_million": 0.1725 }
          }
        }
      ]
    }
    """#

    private func makeFileSync(fileURL: URL, fetchResult: @escaping @Sendable () async throws -> Data) -> NeuralWattCatalogSync {
        NeuralWattCatalogSync(fileURL: fileURL, fetch: fetchResult)
    }

    private func modelsFileURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nw-models-\(UUID().uuidString).json")
    }

    private func loadJSON(_ url: URL) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(contentsOf: url))) as? [String: Any] ?? [:]
    }

    private func neuralwattBlock(_ url: URL) -> [String: Any]? {
        let root = loadJSON(url)
        return (root["providers"] as? [String: Any])?["neuralwatt"] as? [String: Any]
    }

    // MARK: - Reconcile

    func testReconcileCreatesFileWhenAbsent() async {
        let url = modelsFileURL()
        let sync = makeFileSync(fileURL: url) { Data(Self.sampleModelsJSON.utf8) }

        let ids = await sync.reconcile(hasRealKey: true)

        XCTAssertEqual(Set(ids), ["glm-5.2", "kimi-k2.6", "kimi-k2.6-fast"])
        let block = neuralwattBlock(url)
        XCTAssertNotNil(block)
        XCTAssertEqual(block!["baseUrl"] as? String, "https://api.neuralwatt.com/v1")
        XCTAssertEqual(block!["api"] as? String, "openai-completions")
        // Literal placeholder — satisfies pi's "apiKey required" loader, overridden by auth.json.
        XCTAssertEqual(block!["apiKey"] as? String, "placeholder")
        XCTAssertEqual(block!["authHeader"] as? Bool, true)
        XCTAssertEqual(block!["name"] as? String, "NeuralWatt")
        let models = block!["models"] as? [[String: Any]]
        XCTAssertEqual(models?.count, 3)
        // File written with pi's credential permissions (0600), like PiAuthCredentialStore.
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual(attrs?[.posixPermissions] as? NSNumber, NSNumber(value: 0o600))
    }

    func testReconcilePreservesSiblingProviders() async {
        let url = modelsFileURL()
        try? JSONSerialization.data(withJSONObject: [
            "providers": [
                "another-custom": [
                    "baseUrl": "https://example.com",
                    "api": "openai-completions",
                    "apiKey": "$X",
                    "models": [["id": "m1"]],
                ] as [String: Any],
            ] as [String: Any],
        ]).write(to: url)

        let sync = makeFileSync(fileURL: url) { Data(Self.sampleModelsJSON.utf8) }
        _ = await sync.reconcile(hasRealKey: true)

        let root = loadJSON(url)
        let providers = root["providers"] as? [String: Any]
        XCTAssertNotNil(providers?["another-custom"], "sibling provider must survive the neuralwatt merge")
        XCTAssertNotNil(providers?["neuralwatt"])
        // Sibling contents untouched.
        let sibling = providers?["another-custom"] as? [String: Any]
        XCTAssertEqual(sibling?["baseUrl"] as? String, "https://example.com")
    }

    // MARK: - Per-model derivation

    func testReasoningFlagMatchesAPIPerModel() async {
        let url = modelsFileURL()
        let sync = makeFileSync(fileURL: url) { Data(Self.sampleModelsJSON.utf8) }
        _ = await sync.reconcile(hasRealKey: true)

        let models = (neuralwattBlock(url)?["models"] as? [[String: Any]]) ?? []
        func pick(_ id: String) -> [String: Any]? { models.first { $0["id"] as? String == id } }

        XCTAssertEqual(pick("glm-5.2")?["reasoning"] as? Bool, true)
        XCTAssertEqual(pick("kimi-k2.6")?["reasoning"] as? Bool, true)
        XCTAssertEqual(pick("kimi-k2.6-fast")?["reasoning"] as? Bool, false)
    }

    func testReasoningEffortCompatOnlyOnReasoningEffortModels() async {
        let url = modelsFileURL()
        let sync = makeFileSync(fileURL: url) { Data(Self.sampleModelsJSON.utf8) }
        _ = await sync.reconcile(hasRealKey: true)

        let models = (neuralwattBlock(url)?["models"] as? [[String: Any]]) ?? []
        func compat(_ id: String) -> [String: Any]? {
            (models.first { $0["id"] as? String == id })?["compat"] as? [String: Any]
        }

        // glm-5.2 reports reasoning_effort == true → model-level compat enabled.
        XCTAssertEqual(compat("glm-5.2")?["supportsReasoningEffort"] as? Bool, true)
        // kimi-k2.6 reports reasoning_effort == false → no model-level compat (inherits provider default).
        XCTAssertNil(compat("kimi-k2.6"))
        XCTAssertNil(compat("kimi-k2.6-fast"))
    }

    func testMaxTokensOmittedWhenEndpointReportsNull() async {
        let url = modelsFileURL()
        let sync = makeFileSync(fileURL: url) { Data(Self.sampleModelsJSON.utf8) }
        _ = await sync.reconcile(hasRealKey: true)

        let models = (neuralwattBlock(url)?["models"] as? [[String: Any]]) ?? []
        // NeuralWatt reports max_output_tokens == null → field omitted so the UI shows a dash,
        // never pi's fabricated 16384 default.
        for model in models {
            XCTAssertNil(model["maxTokens"], "maxTokens should be omitted when the endpoint reports null")
        }
    }

    func testMaxTokensWrittenWhenEndpointReportsALimit() async {
        // Future-proofing: when NeuralWatt starts reporting a real max_output_tokens, it flows
        // through automatically rather than being dropped to "unknown".
        let jsonWithLimit = #"""
        { "data": [ { "id": "future-model", "metadata": { "display_name": "Future", "capabilities": { "reasoning": true }, "limits": { "max_context_length": 131072, "max_output_tokens": 65536 }, "pricing": {} } } ] }
        """#
        let url = modelsFileURL()
        let sync = makeFileSync(fileURL: url) { Data(jsonWithLimit.utf8) }
        _ = await sync.reconcile(hasRealKey: true)

        let models = (neuralwattBlock(url)?["models"] as? [[String: Any]]) ?? []
        XCTAssertEqual(models.first?["maxTokens"] as? Int, 65536)
    }

    func testCostIsPerMillionNotDivided() async {
        let url = modelsFileURL()
        let sync = makeFileSync(fileURL: url) { Data(Self.sampleModelsJSON.utf8) }
        _ = await sync.reconcile(hasRealKey: true)

        let models = (neuralwattBlock(url)?["models"] as? [[String: Any]]) ?? []
        let glm = models.first { $0["id"] as? String == "glm-5.2" }
        let cost = glm?["cost"] as? [String: Any]
        // pi's cost fields are dollars per million tokens; NeuralWatt's input_per_million is the
        // same unit, so the value passes through verbatim (NOT divided by 1M).
        XCTAssertEqual(cost?["input"] as? Double, 1.45)
        XCTAssertEqual(cost?["output"] as? Double, 4.5)
        XCTAssertEqual(cost?["cacheRead"] as? Double, 0.3625)
        XCTAssertEqual(cost?["cacheWrite"] as? Double, 0)
    }

    // MARK: - Best-effort / failure modes

    func testReconcileLeavesExistingFileUntouchedOnFetchFailure() async {
        let url = modelsFileURL()
        let original: [String: Any] = ["providers": ["neuralwatt": ["name": "Stale"] as [String: Any]] as [String: Any]]
        try? JSONSerialization.data(withJSONObject: original).write(to: url)

        let sync = makeFileSync(fileURL: url) {
            throw URLError(.notConnectedToInternet)
        }
        let ids = await sync.reconcile(hasRealKey: true)

        XCTAssertEqual(ids, [])
        // Existing block preserved — a flaky network never wrecks the file.
        XCTAssertEqual((neuralwattBlock(url)?["name"] as? String), "Stale")
    }

    func testReconcileReturnsEmptyWhenFallbackToZeroModels() async {
        let url = modelsFileURL()
        // Empty catalog: an outage returning []. Must not blank out an existing block.
        try? JSONSerialization.data(withJSONObject: ["providers": ["neuralwatt": ["name": "Keep"] as [String: Any]] as [String: Any]]).write(to: url)

        let sync = makeFileSync(fileURL: url) { Data(#"{"data":[]}"#.utf8) }
        let ids = await sync.reconcile(hasRealKey: true)

        XCTAssertEqual(ids, [])
        XCTAssertEqual((neuralwattBlock(url)?["name"] as? String), "Keep")
    }

    // MARK: - Sign-out gate

    func testReconcileWithoutKeyRemovesBlockSoPiNeverListsWithoutACredential() async {
        // A real key exists -> block is written.
        let url = modelsFileURL()
        let sync = makeFileSync(fileURL: url) { Data(Self.sampleModelsJSON.utf8) }
        _ = await sync.reconcile(hasRealKey: true)
        XCTAssertNotNil(neuralwattBlock(url), "block written when a key exists")

        // Sign-out: no key. The block must be REMOVED, not left with a placeholder, so pi's
        // hasConfiguredAuth never returns true on the placeholder alone and NeuralWatt models
        // never appear without a real credential.
        let ids = await sync.reconcile(hasRealKey: false)

        XCTAssertEqual(ids, [])
        XCTAssertNil(neuralwattBlock(url), "block removed on sign-out")
    }

    func testReconcileWithoutKeyPreservesSiblingProviders() async {
        let url = modelsFileURL()
        try? JSONSerialization.data(withJSONObject: [
            "providers": [
                "neuralwatt": ["name": "NeuralWatt", "models": [["id": "x"]]] as [String: Any],
                "another-custom": ["baseUrl": "https://example.com", "api": "openai-completions", "apiKey": "$X", "models": [["id": "m1"]]] as [String: Any],
            ] as [String: Any],
        ]).write(to: url)

        let sync = makeFileSync(fileURL: url) { Data(Self.sampleModelsJSON.utf8) }
        _ = await sync.reconcile(hasRealKey: false)

        XCTAssertNil(neuralwattBlock(url), "neuralwatt removed")
        let sibling = (loadJSON(url)["providers"] as? [String: Any])?["another-custom"] as? [String: Any]
        XCTAssertNotNil(sibling, "sibling provider survives sign-out removal")
        XCTAssertEqual(sibling?["baseUrl"] as? String, "https://example.com")
    }
}
