import Foundation

/// Bundled source of truth for NeuralWatt as a pi custom provider.
///
/// `~/.pi/agent/models.json` is pi's own config file (see pi's `ModelRegistry`), not Agent Deck's.
/// End users never hand-edit it: `NeuralWattCatalogSync` writes and refreshes the `neuralwatt`
/// block from this spec plus a live fetch of `/v1/models`. The spec here holds only the fields
/// pi can't infer from the models endpoint — the provider identity, auth header convention, the
/// per-model compat rules (which ids accept `reasoning_effort`), and the provider-level compat
/// default. New model ids surfaced by `/v1/models` appear on refresh with no app update.
///
/// See [[project-neuralwatt-native-provider]].
nonisolated enum NeuralWattProviderSpec {
    static let providerID = "neuralwatt"
    static let displayName = "NeuralWatt"
    static let baseURL = "https://api.neuralwatt.com/v1"
    static let api = "openai-completions"
    static let authHeader = true

    /// The NeuralWatt models endpoint. Public (no auth header) — returns the live catalog.
    static let modelsEndpoint = URL(string: "https://api.neuralwatt.com/v1/models")!

    /// Provider-level compat applied to every NeuralWatt model. Model-level compat (below) can
    /// override per id. NeuralWatt serves a `system` role but not a `developer` role, so we pin
    /// `supportsDeveloperRole: false` app-wide here; we deliberately do NOT set
    /// `supportsReasoningEffort` at the provider level (defaults falsy) and enable it per model
    /// only where `/v1/models` reports `reasoning_effort: true`.
    nonisolated(unsafe) static let providerCompat: [String: Any] = [
        "supportsDeveloperRole": false,
    ]

    /// Model ids that accept the `reasoning_effort` parameter. Servers can report
    /// `reasoning_effort: true` while being a non-thinking tier, so this is a curated allowlist
    /// rather than a derivation from `capabilities.reasoning`. Today only the GLM-5.2 family.
    /// When `/v1/models` reports a new model with `reasoning_effort: true`, extend this set.
    static let reasoningEffortModelIDs: Set<String> = [
        "glm-5.2",
        "glm-5.2-fast",
    ]

    /// Model-level `compat` to merge atop `providerCompat`, or nil to inherit the provider default.
    static func compat(forModelID id: String) -> [String: Any]? {
        guard reasoningEffortModelIDs.contains(id) else { return nil }
        return ["supportsReasoningEffort": true]
    }
}
