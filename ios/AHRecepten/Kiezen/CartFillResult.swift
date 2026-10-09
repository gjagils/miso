import Foundation

/// Antwoord op `POST /api/cart/fill`: producten van losse recepten op het AH-lijstje.
struct CartFillResult: Decodable {
    let ok: Bool
    let itemsAdded: Int?
    let unmatched: [String]?
    let error: String?
}
