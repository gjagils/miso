import Foundation

// Zit bij de planningsmodellen omdat `RecipeDetail` (Models.swift) er ook in de deel-extensie naar verwijst.

/// Een tijd uit een bereidingsstap ("20 min") die je als timer kunt starten. De server haalt ze uit de tekst
/// (`cooktime.step_timers`), zodat website en app dezelfde tijden laten zien.
struct StepTimer: Decodable, Hashable, Identifiable, Sendable {
    let seconds: Int
    let label: String

    var id: String { "\(seconds)/\(label)" }

    enum CodingKeys: String, CodingKey { case seconds, label }

    init(seconds: Int, label: String) {
        self.seconds = seconds
        self.label = label
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seconds = c.lenientInt(.seconds) ?? 0
        label = c.lenient(String.self, .label) ?? ""
    }
}
