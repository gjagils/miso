import Foundation

/// `GET /api/ah/search?q=...`. Producten die niet te lezen zijn, worden overgeslagen.
struct AHProductSearchResponse: Decodable, Sendable {
    let products: [AHProduct]
    let error: String?

    private enum CodingKeys: String, CodingKey { case products, error }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let lenient = c.lenient([LenientProduct].self, .products) ?? []
        products = lenient.compactMap(\.product)
        error = c.lenient(String.self, .error)
    }

    private struct LenientProduct: Decodable {
        let product: AHProduct?
        init(from decoder: Decoder) throws {
            product = try? AHProduct(from: decoder)
        }
    }
}
