import XCTest
@testable import MaquetteKit

final class ChatClientTests: XCTestCase {
    func testParseContentDelta() {
        let line = #"data: {"choices":[{"delta":{"content":"hello"}}]}"#
        let delta = ChatClient.parseSSELine(line)
        XCTAssertEqual(delta?.text, "hello")
        XCTAssertEqual(delta?.done, false)
    }

    func testParseDone() {
        let delta = ChatClient.parseSSELine("data: [DONE]")
        XCTAssertNil(delta?.text)
        XCTAssertEqual(delta?.done, true)
    }

    func testParseRoleChunkHasNoText() {
        let line = #"data: {"choices":[{"delta":{"role":"assistant"}}]}"#
        let delta = ChatClient.parseSSELine(line)
        XCTAssertNotNil(delta)
        XCTAssertNil(delta?.text)
        XCTAssertEqual(delta?.done, false)
    }

    func testIgnoresNonDataLines() {
        XCTAssertNil(ChatClient.parseSSELine(""))
        XCTAssertNil(ChatClient.parseSSELine(": keep-alive"))
        XCTAssertNil(ChatClient.parseSSELine("event: ping"))
    }

    func testTextOnlyMessageEncodesAsString() {
        let message = ChatMessage(role: .user, text: "hi")
        let encoded = ChatClient.encode(message: message)
        XCTAssertEqual(encoded["role"] as? String, "user")
        XCTAssertEqual(encoded["content"] as? String, "hi")
    }

    func testMultimodalMessageEncodesAsParts() {
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        let message = ChatMessage(role: .user, content: [.text("score this"), .imagePNG(png)])
        let encoded = ChatClient.encode(message: message)
        let parts = encoded["content"] as? [[String: Any]]
        XCTAssertEqual(parts?.count, 2)
        XCTAssertEqual(parts?[0]["type"] as? String, "text")
        XCTAssertEqual(parts?[1]["type"] as? String, "image_url")
        let imageURL = parts?[1]["image_url"] as? [String: Any]
        XCTAssertEqual(imageURL?["url"] as? String,
                       "data:image/png;base64,\(png.base64EncodedString())")
    }

    private func requestBody(reasoningMaxTokens: Int?) throws -> [String: Any]? {
        let client = ChatClient(endpoint: URL(string: "https://example.com/v1")!,
                                apiKey: "k")
        let request = try client.makeRequest(
            model: "m", messages: [ChatMessage(role: .user, text: "hi")],
            temperature: nil, maxTokens: 8192,
            reasoningMaxTokens: reasoningMaxTokens, stream: false)
        return try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any]
    }

    func testReasoningCapInRequestBody() throws {
        let body = try requestBody(reasoningMaxTokens: 2048)
        let reasoning = body?["reasoning"] as? [String: Any]
        XCTAssertEqual(reasoning?["max_tokens"] as? Int, 2048)
    }

    func testNoReasoningKeyWhenUncapped() throws {
        let body = try requestBody(reasoningMaxTokens: nil)
        XCTAssertNil(body?["reasoning"])
    }

    func testParseCompletionReturnsContentNotReasoning() throws {
        let json = #"""
        {"choices":[{"finish_reason":"stop","message":{"content":"the code",
        "reasoning":"internal thinking"}}],
        "usage":{"prompt_tokens":10,"completion_tokens":20}}
        """#
        let result = try ChatClient.parseCompletion(json.data(using: .utf8)!)
        XCTAssertEqual(result.text, "the code")
        XCTAssertEqual(result.usage?.completionTokens, 20)
    }

    func testParseCompletionTruncatedThrows() {
        // Shape of the real IMG3D-12 diagnostic response: reasoning consumed
        // nearly the whole completion budget and the body stopped on length.
        let json = #"""
        {"choices":[{"finish_reason":"length","message":{"content":"```javascript\nfunc",
        "reasoning":"thinking"}}],
        "usage":{"prompt_tokens":1021,"completion_tokens":8188,
        "completion_tokens_details":{"reasoning_tokens":7865}}}
        """#
        XCTAssertThrowsError(try ChatClient.parseCompletion(json.data(using: .utf8)!)) { error in
            guard case ChatClientError.truncated(let detail) = error else {
                return XCTFail("expected .truncated, got \(error)")
            }
            XCTAssertTrue(detail.contains("7865"))
            XCTAssertTrue(detail.contains("8188"))
        }
    }
}
