import Foundation

/// Eén planregel van de server (`entry` in docs/plan-api.md): dag + soort + personen.
///
/// Alles behalve `date` is optioneel in de JSON, zodat ook oudere servers (zonder `entries`) en
/// toekomstige velden werken.
struct PlanItem: Decodable, Identifiable, Hashable, Sendable {
    /// Stabiel id voor SwiftUI: `entry_id` als die er is, anders afgeleid van dag en inhoud.
    let id: String
    let entryId: Int?
    let date: String
    let kind: PlanKind
    let title: String
    /// Effectief aantal personen (0 = onbekend, oudere server).
    let persons: Int
    /// true = volgt de huishoudgrootte.
    let personsIsDefault: Bool
    let groceryPersons: Int
    let recipeId: Int?
    let recipe: RecipeSummary?
    let text: String
    let extras: [PlanExtra]
    let cookDouble: CookDouble?
    let sourceEntryId: Int?
    let leftoverEntryIds: [Int]

    enum CodingKeys: String, CodingKey {
        case entryId, date, kind, title, persons, personsIsDefault, groceryPersons, recipeId, recipe, text
        case extras, cookDouble, sourceEntryId, leftoverEntryIds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(String.self, forKey: .date)
        entryId = c.lenientInt(.entryId)
        recipe = c.lenient(RecipeSummary.self, .recipe)
        recipeId = c.lenientInt(.recipeId).flatMap { $0 > 0 ? $0 : nil } ?? recipe?.id
        kind = c.lenient(PlanKind.self, .kind) ?? (recipeId == nil ? .stock : .recipe)
        text = c.lenient(String.self, .text) ?? ""
        title = c.lenient(String.self, .title) ?? recipe?.name ?? text
        persons = c.lenientInt(.persons) ?? 0
        personsIsDefault = c.lenient(Bool.self, .personsIsDefault) ?? true
        groceryPersons = c.lenientInt(.groceryPersons) ?? 0
        extras = c.lenient([PlanExtra].self, .extras) ?? []
        cookDouble = c.lenient(String.self, .cookDouble).flatMap(CookDouble.init(rawValue:))
        sourceEntryId = c.lenientInt(.sourceEntryId)
        leftoverEntryIds = c.lenient([Int].self, .leftoverEntryIds) ?? []
        id = entryId.map { "entry/\($0)" } ?? "\(date)/\(kind.rawValue)/\(recipeId ?? 0)/\(title)"
    }

    /// Regel opgebouwd uit het oude `recipes`-veld van `GET /api/week` (server zonder `entries`).
    init(legacy recipe: RecipeSummary, date: String, id: String, persons: Int) {
        self.id = recipe.entryId.map { "entry/\($0)" } ?? id
        entryId = recipe.entryId
        self.date = date
        kind = .recipe
        title = recipe.name
        self.persons = persons
        personsIsDefault = true
        groceryPersons = persons
        recipeId = recipe.id
        self.recipe = recipe
        text = ""
        extras = []
        cookDouble = nil
        sourceEntryId = nil
        leftoverEntryIds = []
    }

    /// Kan de app deze regel aanpassen (verplaatsen, personen, verwijderen)? Alleen met `entry_id`.
    var isEditable: Bool { entryId != nil }

    /// Personen-stepper alleen voor koken en restjes.
    var hasPersons: Bool { kind == .recipe || kind == .leftover }
}
