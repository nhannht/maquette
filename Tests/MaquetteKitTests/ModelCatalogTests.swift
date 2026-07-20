import XCTest
@testable import MaquetteKit

final class ModelCatalogTests: XCTestCase {
    // OpenRouter shape: string prices per token, modalities under architecture.
    private let openRouterJSON = #"""
    {"data":[
      {"id":"google/gemini-3.1-pro-preview",
       "pricing":{"prompt":"0.0000025","completion":"0.00001"},
       "architecture":{"input_modalities":["text","image","file"]}},
      {"id":"qwen/qwen3-coder",
       "pricing":{"prompt":"0.0000002","completion":"0.0000008"},
       "architecture":{"input_modalities":["text"]}},
      {"id":"qwen/qwen3-vl-30b-a3b-instruct",
       "pricing":{"prompt":"0.0000001","completion":"0.0000005"},
       "architecture":{"input_modalities":["text","image"]}},
      {"id":"meta-llama/llama-3.2-11b-vision-instruct:free",
       "pricing":{"prompt":"0","completion":"0"},
       "architecture":{"input_modalities":["text","image"]}}
    ]}
    """#

    func testParseOpenRouterShape() throws {
        let models = try ModelCatalog.parse(Data(openRouterJSON.utf8))
        XCTAssertEqual(models.count, 4)
        let gemini = models[0]
        XCTAssertEqual(gemini.id, "google/gemini-3.1-pro-preview")
        XCTAssertEqual(gemini.promptPrice, 0.0000025)
        XCTAssertTrue(gemini.imageInput)
        XCTAssertFalse(models[1].imageInput)
        XCTAssertTrue(models[3].isFree)
    }

    func testParseBareLocalShape() throws {
        // Ollama / LM Studio list ids only.
        let json = #"{"data":[{"id":"qwen2.5-coder:7b"},{"id":"llava:13b"}]}"#
        let models = try ModelCatalog.parse(Data(json.utf8))
        XCTAssertEqual(models.count, 2)
        XCTAssertNil(models[0].totalPrice)
        XCTAssertEqual(models[0].priceLabel, "price unknown")
    }

    func testParseRejectsGarbage() {
        XCTAssertThrowsError(try ModelCatalog.parse(Data("not json".utf8)))
        XCTAssertThrowsError(try ModelCatalog.parse(Data("{}".utf8)))
    }

    func testCheapestImageCapableForJudge() throws {
        let models = try ModelCatalog.parse(Data(openRouterJSON.utf8))
        let pick = ModelCatalog.cheapest(models, requireImage: true)
        // The free vision model costs zero - cheapest image-capable.
        XCTAssertEqual(pick?.id, "meta-llama/llama-3.2-11b-vision-instruct:free")
    }

    func testCheapestPrefersCodeModelsForCoder() throws {
        let models = try ModelCatalog.parse(Data(openRouterJSON.utf8))
        let pick = ModelCatalog.cheapest(models, requireImage: false,
                                         preferIDContaining: ["coder", "code"])
        XCTAssertEqual(pick?.id, "qwen/qwen3-coder")
    }

    func testPriceLabelPerMillion() throws {
        let models = try ModelCatalog.parse(Data(openRouterJSON.utf8))
        XCTAssertEqual(models[1].priceLabel, "$0.20 + $0.80 /M")
        XCTAssertEqual(models[3].priceLabel, "free")
    }
}
