import Foundation

/// Antwoord op `POST /api/missing/assign`.
struct MissingAssignResponse: Decodable, Sendable {
    let ok: Bool
    let updated: Int?
    let totaal: CoverageTotals?
    let error: String?
}
