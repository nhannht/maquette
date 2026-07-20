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
}
