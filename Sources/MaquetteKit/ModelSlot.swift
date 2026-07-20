import Foundation

/// One configured model endpoint. The sculpt loop uses two: a coder slot that
/// writes the spec and Three.js factory, and a vision slot that scores renders
/// against the reference photo. Both may point at the same model (Kimi K2.5+
/// is natively multimodal).
public struct ModelSlotConfig: Equatable {
    public var endpoint: URL
    public var modelID: String
    /// Empty for keyless local endpoints (Ollama, LM Studio).
    public var apiKey: String
    /// Whether this model reasons before answering. Gates sending the
    /// per-stage reasoning token budget: a reasoning model without the cap
    /// starves its own output (IMG3D-12), while OpenRouter and Ollama simply
    /// ignore the field on non-reasoning models.
    public var reasoning: Bool

    public init(endpoint: URL, modelID: String, apiKey: String,
                reasoning: Bool = true) {
        self.endpoint = endpoint
        self.modelID = modelID
        self.apiKey = apiKey
        self.reasoning = reasoning
    }

    public var client: ChatClient {
        ChatClient(endpoint: endpoint, apiKey: apiKey)
    }

    /// Cheapest possible round trip; returns latency on success.
    public func testConnection() async throws -> Duration {
        let clock = ContinuousClock()
        let start = clock.now
        _ = try await client.complete(
            model: modelID,
            messages: [ChatMessage(role: .user, text: "Reply with the single word: ok")],
            maxTokens: 8)
        return clock.now - start
    }
}
