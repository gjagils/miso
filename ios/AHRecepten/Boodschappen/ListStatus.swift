import Foundation

/// `GET /api/plan/list-status?week=`: staan de boodschappen van elk gerecht al op het AH-lijstje of in de
/// bestelling? Alleen voor weken die nog besteld moeten worden; anders `alreadyOrdered`.
struct ListStatus: Decodable, Equatable, Sendable {
    let ok: Bool
    let connected: Bool
    let week: String
    let entries: [ListStatusEntry]
    let todoCount: Int
    let alreadyOrdered: Bool
    /// Wanneer AH voor het laatst is nagekeken (ISO-tijd); nil = nog nooit. Openen van een scherm
    /// controleert niet bij AH; dat doet alleen de knop "Controleer met AH".
    let checkedAt: String?

    enum CodingKeys: String, CodingKey { case ok, connected, week, entries, todoCount, alreadyOrdered, checkedAt }

    init(ok: Bool = true, connected: Bool = true, week: String = "", entries: [ListStatusEntry] = [],
         alreadyOrdered: Bool = false, checkedAt: String? = nil) {
        self.checkedAt = checkedAt
        self.ok = ok
        self.connected = connected
        self.week = week
        self.entries = entries
        todoCount = entries.filter(\.isTodo).count
        self.alreadyOrdered = alreadyOrdered
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = c.lenient(Bool.self, .ok) ?? true
        connected = c.lenient(Bool.self, .connected) ?? false
        week = c.lenient(String.self, .week) ?? ""
        entries = c.lenient([ListStatusEntry].self, .entries) ?? []
        todoCount = c.lenientInt(.todoCount) ?? entries.filter(\.isTodo).count
        alreadyOrdered = c.lenient(Bool.self, .alreadyOrdered) ?? false
        checkedAt = c.lenient(String.self, .checkedAt).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Kaart tonen: gekoppeld, nog te bestellen, en er staat iets gepland (of het is nog nooit nagekeken
    /// terwijl er wel iets gepland is).
    func showsCard(hasPlanned: Bool) -> Bool {
        connected && !alreadyOrdered && (!entries.isEmpty || (checkedAt == nil && hasPlanned))
    }

    var isChecked: Bool { checkedAt != nil }

    /// "Laatst gecontroleerd: za 10 okt 17:45"
    var checkedText: String {
        guard let checkedAt else { return "Nog niet gecontroleerd of de boodschappen op je AH-lijstje staan." }
        guard let date = Self.parse(checkedAt) else { return "Laatst gecontroleerd: \(checkedAt)" }
        return "Laatst gecontroleerd: \(Self.display.string(from: date))"
    }

    static func parse(_ iso: String) -> Date? {
        let full = ISO8601DateFormatter()
        full.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = full.date(from: iso) { return d }
        full.formatOptions = [.withInternetDateTime]
        if let d = full.date(from: iso) { return d }
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd'T'HH:mm:ss.SSSSSS", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm"] {
            local.dateFormat = format
            if let d = local.date(from: iso) { return d }
        }
        return nil
    }

    private static let display: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "nl_NL")
        f.dateFormat = "EEE d MMM HH:mm"
        return f
    }()

    var readyCount: Int { entries.count - todoEntries.count }
    var todoEntries: [ListStatusEntry] { entries.filter(\.isTodo) }

    /// "3 van 5 gerechten staan klaar op je AH-lijstje of in je bestelling" / "Alle 5 gerechten …  ✓".
    var summary: String {
        let total = entries.count
        if todoEntries.isEmpty {
            return total == 1 ? "Het gerecht staat klaar op je AH-lijstje of in je bestelling ✓"
                              : "Alle \(total) gerechten staan klaar op je AH-lijstje of in je bestelling ✓"
        }
        return "\(readyCount) van \(plural(total, "gerecht", "gerechten")) \(readyCount == 1 ? "staat" : "staan") klaar op je AH-lijstje of in je bestelling"
    }

    /// Status per planregel (voor de badge bij een dag).
    func entry(for entryID: Int?) -> ListStatusEntry? {
        guard let entryID else { return nil }
        return entries.first { $0.entryId == entryID }
    }

    func entries(on date: String) -> [ListStatusEntry] {
        entries.filter { $0.date == date }
    }
}

/// Eén gepland gerecht in de lijststatus.
struct ListStatusEntry: Decodable, Equatable, Identifiable, Sendable {
    var id: String { entryId.map(String.init) ?? "\(date)/\(recipeId ?? 0)" }
    let entryId: Int?
    let date: String
    let recipeId: Int?
    let name: String
    let total: Int
    let present: Int
    let missing: [String]
    let isTodo: Bool

    enum CodingKeys: String, CodingKey { case entryId, date, recipeId, name, total, present, missing, status }

    init(entryId: Int?, date: String, recipeId: Int? = nil, name: String, total: Int, present: Int,
         missing: [String] = [], isTodo: Bool) {
        self.entryId = entryId
        self.date = date
        self.recipeId = recipeId
        self.name = name
        self.total = total
        self.present = present
        self.missing = missing
        self.isTodo = isTodo
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        entryId = c.lenientInt(.entryId)
        date = c.lenient(String.self, .date) ?? ""
        recipeId = c.lenientInt(.recipeId)
        name = c.lenient(String.self, .name) ?? "Recept"
        total = c.lenientInt(.total) ?? 0
        present = c.lenientInt(.present) ?? 0
        missing = c.lenient([String].self, .missing) ?? []
        isTodo = (c.lenient(String.self, .status) ?? "ok") == "todo"
    }

    /// "Lasagne · 4 van 7 producten mist"
    var todoLine: String {
        let count = missing.isEmpty ? max(0, total - present) : missing.count
        return "\(RecipeDisplayName.short(name)) · \(count) van \(plural(total, "product", "producten")) mist"
    }

    var badge: String { isTodo ? "Nog op lijstje zetten" : "Boodschappen ✓" }
}
