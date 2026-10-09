import Foundation

/// Body voor `PATCH /api/plan/entries/{id}`: alleen meegestuurde velden worden aangepast.
struct PlanEntryPatchBody: Encodable, Equatable {
    var date: String?
    var persons: PersonsChange?

    enum CodingKeys: String, CodingKey { case date, persons }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(date, forKey: .date)
        switch persons {
        case .count(let n): try c.encode(n, forKey: .persons)
        case .household: try c.encodeNil(forKey: .persons)
        case nil: break
        }
    }
}
