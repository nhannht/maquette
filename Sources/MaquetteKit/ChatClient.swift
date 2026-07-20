import Foundation

// OpenAI-compatible chat client (Moonshot, OpenRouter, or any /v1 lookalike).
// Text and image content both supported: the sculpt loop sends photos and
// comparison sheets to the vision slot as base64 data URLs.

public enum ChatRole: String {
    case system, user, assistant
}

public enum ChatContent {
    case text(String)
    case imagePNG(Data)
}

public struct ChatMessage {
    public let role: ChatRole
    public let content: [ChatContent]

    public init(role: ChatRole, text: String) {
        self.role = role
        self.content = [.text(text)]
    }

    public init(role: ChatRole, content: [ChatContent]) {
        self.role = role
        self.content = content
    }
}

public struct ChatUsage {
    public let promptTokens: Int
    public let completionTokens: Int
}

public struct ChatResult {
    public let text: String
    public let usage: ChatUsage?
}

public enum ChatClientError: Error, CustomStringConvertible {
    case http(status: Int, body: String)
    case malformedResponse(String)
    case truncated(String)

    public var description: String {
        switch self {
        case .http(let status, let body): return "HTTP \(status): \(body.prefix(300))"
        case .malformedResponse(let detail): return "malformed response: \(detail)"
        case .truncated(let detail): return "completion truncated: \(detail)"
        }
    }
}

public struct ChatClient {
    public let endpoint: URL
    public let apiKey: String

    public init(endpoint: URL, apiKey: String) {
        self.endpoint = endpoint
        self.apiKey = apiKey
    }

    /// Stream assistant text deltas for a chat completion.
    public func stream(model: String, messages: [ChatMessage],
                       temperature: Double? = nil,
                       maxTokens: Int? = nil,
                       reasoningMaxTokens: Int? = nil) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try makeRequest(model: model, messages: messages,
                                                  temperature: temperature,
                                                  maxTokens: maxTokens,
                                                  reasoningMaxTokens: reasoningMaxTokens,
                                                  stream: true)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw ChatClientError.malformedResponse("not an HTTP response")
                    }
                    guard http.statusCode == 200 else {
                        var body = ""
                        for try await line in bytes.lines { body += line + "\n" }
                        throw ChatClientError.http(status: http.statusCode, body: body)
                    }
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        guard let delta = Self.parseSSELine(line) else { continue }
                        if delta.done { break }
                        if let text = delta.text { continuation.yield(text) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Non-streaming completion. The sculpt loop uses this instead of stream:
    /// the JSON body of a non-streamed response carries the usage block, which
    /// is the only portable way to get token counts for cost accounting.
    public func completeOnce(model: String, messages: [ChatMessage],
                             temperature: Double? = nil,
                             maxTokens: Int? = nil,
                             reasoningMaxTokens: Int? = nil) async throws -> ChatResult {
        let request = try makeRequest(model: model, messages: messages,
                                      temperature: temperature,
                                      maxTokens: maxTokens,
                                      reasoningMaxTokens: reasoningMaxTokens,
                                      stream: false)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ChatClientError.malformedResponse("not an HTTP response")
        }
        guard http.statusCode == 200 else {
            throw ChatClientError.http(status: http.statusCode,
                                       body: String(data: data, encoding: .utf8) ?? "")
        }
        return try Self.parseCompletion(data)
    }

    /// Decode a non-streamed completion body. A finish_reason of "length" is a
    /// hard error, not a result: reasoning models share max_tokens between
    /// thinking and output, so a length-stopped body is either cut-off code or
    /// leaked reasoning prose - never something to hand downstream (IMG3D-12).
    /// The message's `reasoning` field is deliberately never read as content.
    static func parseCompletion(_ data: Data) throws -> ChatResult {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let choice = choices.first,
              let message = choice["message"] as? [String: Any] else {
            throw ChatClientError.malformedResponse(String(data: data, encoding: .utf8)?
                .prefix(300).description ?? "unreadable body")
        }
        var usage: ChatUsage?
        var reasoningTokens: Int?
        if let u = obj["usage"] as? [String: Any] {
            usage = ChatUsage(promptTokens: u["prompt_tokens"] as? Int ?? 0,
                              completionTokens: u["completion_tokens"] as? Int ?? 0)
            let details = u["completion_tokens_details"] as? [String: Any]
            reasoningTokens = details?["reasoning_tokens"] as? Int
        }
        if choice["finish_reason"] as? String == "length" {
            var detail = "hit max_tokens before completing"
            if let usage, let reasoningTokens {
                detail += " (reasoning consumed \(reasoningTokens) of "
                    + "\(usage.completionTokens) completion tokens)"
            }
            throw ChatClientError.truncated(detail)
        }
        let text: String
        if let content = message["content"] as? String {
            text = content
        } else if let parts = message["content"] as? [[String: Any]] {
            text = parts.compactMap { $0["text"] as? String }.joined()
        } else {
            throw ChatClientError.malformedResponse("message has no content")
        }
        return ChatResult(text: text, usage: usage)
    }

    /// Convenience: run a completion to the end and return the full text.
    public func complete(model: String, messages: [ChatMessage],
                         temperature: Double? = nil,
                         maxTokens: Int? = nil,
                         reasoningMaxTokens: Int? = nil) async throws -> String {
        var out = ""
        for try await delta in stream(model: model, messages: messages,
                                      temperature: temperature, maxTokens: maxTokens,
                                      reasoningMaxTokens: reasoningMaxTokens) {
            out += delta
        }
        return out
    }

    // MARK: - Wire format

    struct SSEDelta {
        let text: String?
        let done: Bool
    }

    /// One SSE line -> content delta. Returns nil for keep-alives, comments,
    /// and role/finish chunks that carry no text.
    static func parseSSELine(_ line: String) -> SSEDelta? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload.isEmpty { return nil }
        if payload == "[DONE]" { return SSEDelta(text: nil, done: true) }
        guard let data = payload.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let first = choices.first else { return nil }
        let delta = first["delta"] as? [String: Any]
        return SSEDelta(text: delta?["content"] as? String, done: false)
    }

    func makeRequest(model: String, messages: [ChatMessage],
                     temperature: Double?, maxTokens: Int?,
                     reasoningMaxTokens: Int?,
                     stream: Bool) throws -> URLRequest {
        var body: [String: Any] = [
            "model": model,
            "messages": messages.map(Self.encode(message:)),
            "stream": stream,
        ]
        if let temperature { body["temperature"] = temperature }
        if let maxTokens { body["max_tokens"] = maxTokens }
        // OpenRouter's normalized reasoning control. A token cap is the only
        // variant that actually protects the output budget: exclude:true still
        // burns the budget and leaks thinking prose into content (IMG3D-12
        // diagnostic). Providers treat the cap as advisory (Gemini overshoots
        // ~2x), so pair it with headroom in max_tokens.
        if let reasoningMaxTokens {
            body["reasoning"] = ["max_tokens": reasoningMaxTokens]
        }

        var request = URLRequest(url: endpoint.appending(path: "chat/completions"))
        request.httpMethod = "POST"
        // Local endpoints (Ollama, LM Studio) are keyless; only send the
        // header when a key exists.
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 600
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Pure-text messages encode content as a plain string (maximum endpoint
    /// compatibility); anything with an image uses the multimodal parts array.
    static func encode(message: ChatMessage) -> [String: Any] {
        if message.content.count == 1, case .text(let text) = message.content[0] {
            return ["role": message.role.rawValue, "content": text]
        }
        let parts: [[String: Any]] = message.content.map { part in
            switch part {
            case .text(let text):
                return ["type": "text", "text": text]
            case .imagePNG(let data):
                let url = "data:image/png;base64,\(data.base64EncodedString())"
                return ["type": "image_url", "image_url": ["url": url]]
            }
        }
        return ["role": message.role.rawValue, "content": parts]
    }
}
