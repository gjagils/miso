import Foundation

/// Body voor `PATCH /api/freezer/{id}`; `portions: 0` verwijdert het item.
struct FreezerPortionsBody: Encodable {
    let portions: Int
}
