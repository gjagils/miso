import Foundation

/// Body voor `POST /api/plan/propose`: wens per datum (chip-sleutel of gerecht als tekst).
struct ProposeBody: Encodable, Equatable {
    let week: String
    let wishes: [String: String]
    /// Dagen die je via "Wijzig" opnieuw kiest: die tellen voor de server als open.
    var replace: [String] = []
}

/// Body voor `POST /api/plan/wishes-text`: één zin, Claude maakt er wensen per dag van.
struct WishesTextBody: Encodable, Equatable {
    let week: String
    let text: String
}

/// Body voor `POST /api/plan/apply`.
struct PlanApplyBody: Encodable, Equatable {
    let week: String
    let choices: [PlanApplyChoice]
    /// Eerste voorstellen die je wegwisselde (zwak negatief signaal voor Miso).
    let swapped: [Int]
}
