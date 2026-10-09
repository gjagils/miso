import Foundation

/// `GET /api/missing`.
struct MissingResponse: Decodable, Sendable {
    let groups: [MissingGroup]
    let totaal: CoverageTotals
}
