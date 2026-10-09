import Foundation
import Observation

/// Toestand en acties van het Inplannen-scherm. Spiegelt `backend/app/static/plan.js`.
@MainActor
@Observable
final class PlanSheetModel {
    let request: PlanSheetRequest
    private(set) var household = 4
    var tab: PlanSheetTab
    private(set) var start: String
    private(set) var date: String?
    var persons: Int
    var cookDoubleOn: Bool
    var cookDoubleChoice: CookDouble
    private(set) var chosen: PlanRecipeChoice?

    // Recept zoeken
    var query = ""
    private(set) var ownRecipes: [RecipeSummary] = []
    private(set) var ahHits: [AHRecipeHit] = []
    private(set) var ahStatus: String?
    private(set) var ahSearching = false

    // Uit de vriezer / hebben we al
    private(set) var freezer: [FreezerItem] = []
    private(set) var selectedFreezer: FreezerItem?
    var stockText = ""
    var extrasText = ""
    /// De tekst is automatisch ingevuld vanuit een vriezer-item (en mag dus weer automatisch weg).
    private var stockTextIsAuto = false

    private(set) var chips: [DayChip] = []
    /// Tekst op de knop terwijl er iets loopt.
    private(set) var busy: String?
    var errorText: String?

    private let today = KiezenDates.today
    private var chipRequest = 0
    private var ahRequest = 0
    private var personsTouched = false

    init(request: PlanSheetRequest) {
        self.request = request
        var initialTab = request.freezerItem == nil ? request.tab : .stock
        if case .move(let item) = request.mode { initialTab = item.kind == .stock ? .stock : .recipe }
        tab = initialTab
        let moveItem: PlanItem? = if case .move(let item) = request.mode { item } else { nil }
        let window = DayChipBuilder.initialWindow(start: request.start, date: request.date ?? moveItem?.date,
                                                  today: KiezenDates.today, chooseDefault: request.mode == .plan)
        start = window.start
        date = window.date
        persons = request.persons ?? moveItem.map { max($0.persons, 1) } ?? 4
        personsTouched = request.persons != nil || moveItem != nil
        cookDoubleOn = request.cookDouble != nil
        cookDoubleChoice = request.cookDouble ?? .tomorrow
        chosen = request.recipe
        if let item = request.freezerItem {
            selectedFreezer = item
            stockText = "\(item.name) uit de vriezer"
            stockTextIsAuto = true
        }
    }

    // MARK: Afgeleide waarden

    var moveItem: PlanItem? {
        if case .move(let item) = request.mode { item } else { nil }
    }

    var isMove: Bool { moveItem != nil }
    var showsTabs: Bool { request.showTabs && !isMove }
    var showsPersons: Bool { moveItem.map(\.hasPersons) ?? (tab == .recipe) }
    var showsCookDouble: Bool { !isMove && tab == .recipe }
    var canChangeRecipe: Bool { request.showTabs }

    var title: String {
        if let moveItem { return "\(moveItem.title) verplaatsen" }
        if let recipe = request.recipe, !request.showTabs { return recipe.name }
        if let date { return "Wat eten we \(KiezenDates.weekdayName(date).lowercased())?" }
        return "Inplannen"
    }

    var submitLabel: String {
        switch request.mode {
        case .move: "Opslaan"
        case .pick: "Klaar"
        case .plan: "Inplannen"
        }
    }

    var dayInfo: String { DayChipBuilder.info(for: date, chips: chips) }

    /// Eigen recepten die bij de zoekterm passen (alle woorden), max 6 zonder en 12 met zoekterm.
    var ownHits: [RecipeSummary] {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        let hits = ownRecipes.filter { recipe in terms.allSatisfy { recipe.name.localizedStandardContains($0) } }
        return Array(hits.prefix(terms.isEmpty ? 6 : 12))
    }

    /// Allerhande-resultaten die nog niet als eigen recept bestaan, max 8.
    var ahResults: [AHRecipeHit] {
        let ownNames = Set(ownRecipes.map(\.name))
        return Array(ahHits.filter { !ownNames.contains($0.title) }.prefix(8))
    }

    var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    // MARK: Laden

    func load(api: API) async {
        if let settings = try? await api.planSettings() {
            household = settings.householdSize
            if !personsTouched { persons = household }
        }
        await loadChips(api: api)
        if showsTabs, ownRecipes.isEmpty {
            ownRecipes = (try? await api.recipes()) ?? []
        }
    }

    func loadChips(api: API) async {
        chipRequest += 1
        let mine = chipRequest
        let entries = (try? await api.planEntries(start: start))?.entries ?? []
        guard mine == chipRequest else { return }
        chips = DayChipBuilder.chips(start: start, today: today, entries: entries, ignoring: moveItem?.entryId)
    }

    /// Bij het wisselen naar "Uit de vriezer / hebben we al" de vriezer ophalen.
    func tabDidChange(api: API) async {
        guard tab == .stock, !isMove else { return }
        freezer = (try? await api.freezerItems()) ?? []
    }

    // MARK: Dagen en personen

    func shiftWeek(_ days: Int, api: API) async {
        start = KiezenDates.add(start, days)
        await loadChips(api: api)
    }

    func select(_ chip: DayChip) {
        guard !chip.isPast else { return }
        date = chip.date
        errorText = nil
    }

    func setPersons(_ value: Int) {
        persons = min(max(value, 1), 20)
        personsTouched = true
    }

    // MARK: Recept zoeken

    func choose(_ choice: PlanRecipeChoice) {
        chosen = choice
        errorText = nil
    }

    func clearChoice() {
        chosen = nil
    }

    /// Allerhande zoeken (na 350 ms, zoals de web-versie). Eigen recepten filteren gaat direct via `ownHits`.
    func search(api: API) async {
        guard showsTabs else { return }
        let q = trimmedQuery
        guard q.count >= 2 else {
            ahHits = []
            ahStatus = nil
            ahSearching = false
            return
        }
        try? await Task.sleep(for: .milliseconds(350))
        if Task.isCancelled { return }
        ahRequest += 1
        let mine = ahRequest
        ahSearching = true
        defer { if mine == ahRequest { ahSearching = false } }
        do {
            let hits = try await api.searchAllerhande(q)
            guard mine == ahRequest, !Task.isCancelled else { return }
            ahHits = hits
            ahStatus = ahResults.isEmpty ? "Niets extra gevonden in Allerhande voor \"\(q)\"." : nil
        } catch {
            guard mine == ahRequest, !Task.isCancelled, (error as? URLError)?.code != .cancelled else { return }
            ahHits = []
            ahStatus = error.localizedDescription
        }
    }

    // MARK: Vriezer

    func toggleFreezer(_ item: FreezerItem) {
        if selectedFreezer?.id == item.id {
            selectedFreezer = nil
            if stockTextIsAuto {
                stockText = ""
                stockTextIsAuto = false
            }
        } else {
            selectedFreezer = item
            if stockText.isEmpty || stockTextIsAuto {
                stockText = "\(item.name) uit de vriezer"
                stockTextIsAuto = true
            }
        }
    }

    /// De gebruiker typte zelf: niet meer automatisch overschrijven.
    func stockTextEdited() {
        if let item = selectedFreezer, stockText != "\(item.name) uit de vriezer" { stockTextIsAuto = false }
    }

    // MARK: Opslaan

    /// Voert de keuze uit. Geeft nil terug bij een fout (die staat dan in `errorText`).
    func submit(api: API) async -> PlanSheetResult? {
        errorText = nil
        guard let date else {
            errorText = "Kies een dag."
            return nil
        }
        let cookDouble = showsCookDouble && cookDoubleOn ? cookDoubleChoice : nil
        if case .pick = request.mode {
            return .picked(date: date, persons: persons, cookDouble: cookDouble)
        }
        busy = "Bezig..."
        defer { busy = nil }
        do {
            if let item = moveItem, let entryID = item.entryId {
                var body = PlanEntryPatchBody(date: date)
                if item.hasPersons && persons != item.persons { body.persons = .from(persons, household: household) }
                return .moved(try await api.updatePlanEntry(entryID, body))
            }
            if tab == .stock {
                let text = stockText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty || selectedFreezer != nil else {
                    errorText = "Vul in wat jullie eten."
                    return nil
                }
                let extras = extrasText.split(whereSeparator: \.isNewline)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                return .saved(try await api.createPlanEntry(
                    .stock(date: date, text: text, extras: extras, freezerItemId: selectedFreezer?.id)))
            }
            guard let choice = chosen else {
                errorText = "Kies eerst een recept."
                return nil
            }
            var recipeID = choice.recipeID
            if choice.source == .allerhande {
                busy = "Recept ophalen..."
                let added = try await api.addAllerhande(id: choice.recipeID)
                guard added.ok, let id = added.id else {
                    errorText = added.error ?? "Recept ophalen bij AH mislukt."
                    return nil
                }
                recipeID = id
                chosen = PlanRecipeChoice(source: .own, recipeID: id, name: choice.name, imageUrl: choice.imageUrl, meta: choice.meta)
                busy = "Bezig..."
            }
            let body = PlanEntryCreateBody.recipe(recipeID, date: date,
                                                  persons: persons == household ? nil : persons,
                                                  cookDouble: cookDouble)
            return .saved(try await api.createPlanEntry(body))
        } catch {
            errorText = "Opslaan mislukt. \(error.localizedDescription)"
            return nil
        }
    }
}
