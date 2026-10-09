import Foundation

/// Koppelkwaliteit over alle recepten (`totaal` in `/api/missing` en `/api/missing/assign`).
struct CoverageTotals: Decodable, Equatable, Sendable {
    /// Percentage gekoppelde ingrediënten (van wat gekocht moet worden).
    let pct: Double
    /// Recepten zonder open ingrediënten.
    let volledig: Int
    let recepten: Int
    /// Open ingrediëntregels; ontbreekt bij oudere servers.
    let open: Int?

    private enum CodingKeys: String, CodingKey { case pct, volledig, recepten, open }

    init(pct: Double, volledig: Int, recepten: Int, open: Int? = nil) {
        self.pct = pct
        self.volledig = volledig
        self.recepten = recepten
        self.open = open
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pct = c.lenient(Double.self, .pct) ?? 0
        volledig = c.lenientInt(.volledig) ?? 0
        recepten = c.lenientInt(.recepten) ?? 0
        open = c.lenientInt(.open)
    }

    /// 0...1 voor een voortgangsbalk.
    var fraction: Double { min(max(pct / 100, 0), 1) }

    /// "94,3%".
    var pctText: String {
        (pct / 100).formatted(.percent.precision(.fractionLength(0...1)).locale(Locale(identifier: "nl_NL")))
    }

    /// "88 van 141 recepten compleet".
    var completeText: String {
        "\(volledig) van \(plural(recepten, "recept", "recepten")) compleet"
    }
}
