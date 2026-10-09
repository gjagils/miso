import Foundation

/// Boodschappen-status van volgende week (onderdeel van `next-week-status`).
struct NextWeekListStatus: Decodable, Equatable, Sendable {
    let needed: Int
    let missingCount: Int
    let unmatchedCount: Int
    let complete: Bool

    enum CodingKeys: String, CodingKey { case needed, missingCount, unmatchedCount, complete }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        needed = c.lenientInt(.needed) ?? 0
        missingCount = c.lenientInt(.missingCount) ?? 0
        unmatchedCount = c.lenientInt(.unmatchedCount) ?? 0
        complete = c.lenient(Bool.self, .complete) ?? false
    }
}
