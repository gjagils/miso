import Foundation

/// Extra boodschap bij een voorraad-dag ("spaghetti"), eventueel gekoppeld aan een AH-product.
struct PlanExtra: Decodable, Hashable, Sendable {
    let text: String
    let product: String?
    let productId: Int?
    let productImage: String?

    init(text: String, product: String? = nil, productId: Int? = nil, productImage: String? = nil) {
        self.text = text
        self.product = product
        self.productId = productId
        self.productImage = productImage
    }

    enum CodingKeys: String, CodingKey { case text, product, productId, productImage }

    init(from decoder: Decoder) throws {
        // Oudere vorm: alleen een string.
        if let text = try? decoder.singleValueContainer().decode(String.self) {
            self.init(text: text)
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(text: c.lenient(String.self, .text) ?? "",
                  product: c.lenient(String.self, .product),
                  productId: c.lenientInt(.productId),
                  productImage: c.lenient(String.self, .productImage))
    }
}
