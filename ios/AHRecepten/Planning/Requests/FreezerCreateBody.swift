import Foundation

/// Body voor `POST /api/freezer`.
struct FreezerCreateBody: Encodable {
    let name: String
    let portions: Int
}
