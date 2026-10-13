import Foundation

/// "3 recepten van jullie zitten volgende week in de bonus ...": onderdeel van `GET /api/plan/next-week-status`.
struct BonusHint: Decodable, Equatable, Sendable {
    let count: Int
    let saving: Double
    let names: [String]
    /// Kant-en-klare zin; leeg als er (nog) geen bonus bekend is.
    let message: String

    enum CodingKeys: String, CodingKey { case count, saving, names, message }

    init(count: Int = 0, saving: Double = 0, names: [String] = [], message: String = "") {
        self.count = count
        self.saving = saving
        self.names = names
        self.message = message
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(count: c.lenientInt(.count) ?? 0, saving: c.lenient(Double.self, .saving) ?? 0,
                  names: c.lenient([String].self, .names) ?? [], message: c.lenient(String.self, .message) ?? "")
    }

    var isUseful: Bool { count > 0 && !message.isEmpty }
}
