import Foundation

/// Gezondheidsprofiel van een recept (schatting door Claude), voor de chips per dag.
struct HealthProfile: Decodable, Hashable, Sendable {
    let kcal: Int?
    let eiwit: String?
    let basis: String?
    let keuken: String?

    enum CodingKeys: String, CodingKey { case kcal, eiwit, basis, keuken }

    init(kcal: Int? = nil, eiwit: String? = nil, basis: String? = nil, keuken: String? = nil) {
        self.kcal = kcal
        self.eiwit = eiwit
        self.basis = basis
        self.keuken = keuken
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(kcal: c.lenientInt(.kcal), eiwit: c.lenient(String.self, .eiwit),
                  basis: c.lenient(String.self, .basis), keuken: c.lenient(String.self, .keuken))
    }

    /// Chips zoals op de web-versie: eiwit, basis, ~kcal.
    var chips: [String] {
        var out = [eiwit, basis].compactMap { $0 }.filter { !$0.isEmpty }
        if let kcal, kcal > 0 { out.append("~\(kcal) kcal") }
        return out
    }
}
