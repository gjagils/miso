import Foundation

/// Body voor `POST /api/missing/assign`: één product voor alle regels van een groep, of `null` = niet nodig.
struct MissingAssignBody: Encodable, Sendable {
    let lines: [MissingLine]
    let product: AHProduct?

    private enum CodingKeys: String, CodingKey { case lines, product }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(lines, forKey: .lines)
        try c.encode(product, forKey: .product) // nil wordt bewust `null` (= niet nodig)
    }
}
