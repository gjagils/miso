import Foundation

/// Iets in de vriezer, met het aantal porties.
struct FreezerItem: Decodable, Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let portions: Int
    let addedOn: String?
    let fromRecipeId: Int?
    /// Hoe lang al in de vriezer ("5 dagen", "3 weken", "4 maanden"); nil bij oudere servers.
    let ageLabel: String?
    /// "" | "soon" (vanaf 60 dagen) | "old" (vanaf 90 dagen).
    let ageState: String

    enum CodingKeys: String, CodingKey { case id, name, portions, addedOn, fromRecipeId, ageLabel, ageState }

    init(id: Int, name: String, portions: Int, addedOn: String? = nil, fromRecipeId: Int? = nil,
         ageLabel: String? = nil, ageState: String = "") {
        self.ageLabel = ageLabel
        self.ageState = ageState
        self.id = id
        self.name = name
        self.portions = portions
        self.addedOn = addedOn
        self.fromRecipeId = fromRecipeId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.lenientInt(.id) else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "vriezer-item zonder id")
        }
        self.init(id: id,
                  name: c.lenient(String.self, .name) ?? "",
                  portions: c.lenientInt(.portions) ?? 1,
                  addedOn: c.lenient(String.self, .addedOn),
                  fromRecipeId: c.lenientInt(.fromRecipeId),
                  ageLabel: c.lenient(String.self, .ageLabel),
                  ageState: c.lenient(String.self, .ageState) ?? "")
    }

    var isOld: Bool { ageState == "old" }
    var isGettingOld: Bool { ageState == "soon" || ageState == "old" }

    /// "al 4 maanden: snel opeten" / "2 maanden in de vriezer"; nil als er niets te waarschuwen valt.
    var ageWarning: String? {
        guard isGettingOld, let ageLabel, !ageLabel.isEmpty else { return nil }
        return isOld ? "al \(ageLabel): snel opeten" : "\(ageLabel) in de vriezer"
    }
}
