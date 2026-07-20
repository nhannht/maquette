import Foundation

/// One entry from an endpoint's /models list. Prices are USD per token when
/// the endpoint publishes them (OpenRouter does); local endpoints (Ollama,
/// LM Studio) list bare ids - nil prices, unknown modality.
public struct ModelInfo: Identifiable, Equatable, Sendable {
    public let id: String
    public let promptPrice: Double?
    public let completionPrice: Double?
    public let imageInput: Bool

    public var totalPrice: Double? {
        guard let promptPrice, let completionPrice else { return nil }
        return promptPrice + completionPrice
    }

    public var isFree: Bool { totalPrice == 0 }

    /// "free", "$0.20 + $0.80 /M" or "price unknown" for pickers.
    public var priceLabel: String {
        guard let promptPrice, let completionPrice else { return "price unknown" }
        if isFree { return "free" }
        let perM = { (price: Double) in String(format: "$%.2f", price * 1_000_000) }
        return "\(perM(promptPrice)) + \(perM(completionPrice)) /M"
    }
}

public enum ModelCatalogError: Error, CustomStringConvertible {
    case badResponse(String)

    public var description: String {
        switch self {
        case .badResponse(let detail): return "model list fetch failed: \(detail)"
        }
    }
}

public enum ModelCatalog {
    /// GET {endpoint}/models - the standard OpenAI-compatible listing.
    /// OpenRouter serves it keyless with pricing and modalities.
    public static func fetch(endpoint: URL, apiKey: String) async throws -> [ModelInfo] {
        var request = URLRequest(url: endpoint.appending(path: "models"))
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw ModelCatalogError.badResponse("HTTP \(code)")
        }
        return try parse(data)
    }

    static func parse(_ data: Data) throws -> [ModelInfo] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = root["data"] as? [[String: Any]] else {
            throw ModelCatalogError.badResponse("no data array in /models response")
        }
        return list.compactMap { entry in
            guard let id = entry["id"] as? String else { return nil }
            let pricing = entry["pricing"] as? [String: Any]
            let modalities = (entry["architecture"] as? [String: Any])?["input_modalities"]
                as? [String] ?? []
            return ModelInfo(id: id,
                             promptPrice: price(pricing?["prompt"]),
                             completionPrice: price(pricing?["completion"]),
                             imageInput: modalities.contains("image"))
        }
    }

    /// The "just works" default: cheapest model that fits. requireImage
    /// filters to image-capable models (the judge must see renders); hints
    /// prefer ids containing any of the given substrings (e.g. code models
    /// for the coder slot) when such models exist. Unpriced models lose to
    /// priced ones; free models win by costing zero.
    public static func cheapest(_ models: [ModelInfo], requireImage: Bool,
                                preferIDContaining hints: [String] = []) -> ModelInfo? {
        var pool = requireImage ? models.filter(\.imageInput) : models
        if !hints.isEmpty {
            let hinted = pool.filter { model in
                hints.contains { model.id.localizedCaseInsensitiveContains($0) }
            }
            if !hinted.isEmpty { pool = hinted }
        }
        return pool.min { a, b in
            (a.totalPrice ?? .infinity) < (b.totalPrice ?? .infinity)
        }
    }

    private static func price(_ value: Any?) -> Double? {
        if let string = value as? String { return Double(string) }
        if let number = value as? Double { return number }
        return nil
    }
}
