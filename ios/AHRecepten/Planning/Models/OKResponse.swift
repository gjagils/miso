import Foundation

/// Response met alleen `ok` (bijv. `DELETE /api/freezer/{id}`).
struct OKResponse: Decodable, Sendable {
    let ok: Bool
}
