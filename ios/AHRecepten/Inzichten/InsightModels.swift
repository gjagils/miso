import Foundation

// Modellen voor kosten, uitgaven en "waarschijnlijk op" (docs/plan-api.md, "AH-datalaag en inzichten").
// Alles lenient: een oudere server zonder deze endpoints geeft gewoon niets te zien.

/// `GET /api/recipes/{id}/cost`
struct RecipeCost: Decodable, Equatable, Sendable {
    let total: Double
    let bonusSaving: Double
    let persons: Int
    let perPerson: Double?
    let knownCount: Int
    let complete: Bool

    enum CodingKeys: String, CodingKey { case total, bonusSaving, persons, perPerson, knownCount, complete }

    init(total: Double = 0, bonusSaving: Double = 0, persons: Int = 4, perPerson: Double? = nil, knownCount: Int = 0,
         complete: Bool = false) {
        self.total = total
        self.bonusSaving = bonusSaving
        self.persons = persons
        self.perPerson = perPerson
        self.knownCount = knownCount
        self.complete = complete
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        total = c.lenient(Double.self, .total) ?? 0
        bonusSaving = c.lenient(Double.self, .bonusSaving) ?? 0
        persons = c.lenientInt(.persons) ?? 4
        perPerson = c.lenient(Double.self, .perPerson)
        knownCount = c.lenientInt(.knownCount) ?? 0
        complete = c.lenient(Bool.self, .complete) ?? false
    }

    /// Zonder bekende prijzen valt er niets te tonen.
    var isUsable: Bool { knownCount > 0 }

    /// "Ongeveer € 6,00 voor 4 (€ 1,50 p.p.), € 0,30 bonusvoordeel, niet alles heeft een prijs"
    var summary: String {
        var text = "Ongeveer \(Euro.format(total)) voor \(persons)"
        if let perPerson { text += " (\(Euro.format(perPerson)) p.p.)" }
        if bonusSaving > 0 { text += ", \(Euro.format(bonusSaving)) bonusvoordeel" }
        if !complete { text += ", niet alles heeft een prijs" }
        return text
    }
}

/// `GET /api/week/cost`
struct WeekCost: Decodable, Equatable, Sendable {
    let total: Double
    let bonusSaving: Double
    let perMeal: Double?
    let knownCount: Int
    let unknown: [String]
    /// Weekbudget in euro's (nil = geen), en hoeveel procent de schatting en wat er echt is uitgegeven daarvan is.
    let budget: Int?
    let budgetPct: Int?
    let actual: Double?
    let actualPct: Int?

    enum CodingKeys: String, CodingKey { case total, bonusSaving, perMeal, knownCount, unknown, budget, budgetPct, actual, actualPct }

    init(total: Double = 0, bonusSaving: Double = 0, perMeal: Double? = nil, knownCount: Int = 0, unknown: [String] = [],
         budget: Int? = nil, budgetPct: Int? = nil, actual: Double? = nil, actualPct: Int? = nil) {
        self.budget = budget
        self.budgetPct = budgetPct
        self.actual = actual
        self.actualPct = actualPct
        self.total = total
        self.bonusSaving = bonusSaving
        self.perMeal = perMeal
        self.knownCount = knownCount
        self.unknown = unknown
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        total = c.lenient(Double.self, .total) ?? 0
        bonusSaving = c.lenient(Double.self, .bonusSaving) ?? 0
        perMeal = c.lenient(Double.self, .perMeal)
        knownCount = c.lenientInt(.knownCount) ?? 0
        unknown = c.lenient([String].self, .unknown) ?? []
        budget = c.lenientInt(.budget)
        budgetPct = c.lenientInt(.budgetPct)
        actual = c.lenient(Double.self, .actual)
        actualPct = c.lenientInt(.actualPct)
    }

    var isUsable: Bool { knownCount > 0 }

    /// "Budget € 120,00 · geschat 45% · werkelijk € 90,00 (75%)"; nil zonder budget.
    var budgetText: String? {
        guard let budget, let budgetPct else { return nil }
        var text = "Budget \(Euro.format(Double(budget))) · geschat \(budgetPct)%"
        if let actual, let actualPct { text += " · werkelijk \(Euro.format(actual)) (\(actualPct)%)" }
        return text
    }
    var overBudget: Bool { (budgetPct ?? 0) > 100 }

    /// "Geschat € 54,20 voor deze week · € 2,10 per bord · waarvan € 3,00 bonusvoordeel · 2 producten zonder prijs"
    var summary: String {
        var parts = ["Geschat \(Euro.format(total)) voor deze week"]
        if let perMeal { parts.append("\(Euro.format(perMeal)) per bord") }
        if bonusSaving > 0 { parts.append("waarvan \(Euro.format(bonusSaving)) bonusvoordeel") }
        if !unknown.isEmpty { parts.append("\(plural(unknown.count, "product", "producten")) zonder prijs") }
        return parts.joined(separator: " · ")
    }
}

/// Eén week uit `GET /api/spend`.
struct SpendWeek: Decodable, Identifiable, Equatable, Sendable {
    let week: String
    let total: Double
    let discount: Double
    let trips: Int
    let unknown: Int

    var id: String { week }

    enum CodingKeys: String, CodingKey { case week, total, discount, trips, unknown }

    init(week: String, total: Double = 0, discount: Double = 0, trips: Int = 0, unknown: Int = 0) {
        self.week = week
        self.total = total
        self.discount = discount
        self.trips = trips
        self.unknown = unknown
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        week = c.lenient(String.self, .week) ?? ""
        total = c.lenient(Double.self, .total) ?? 0
        discount = c.lenient(Double.self, .discount) ?? 0
        trips = c.lenientInt(.trips) ?? 0
        unknown = c.lenientInt(.unknown) ?? 0
    }
}

struct SpendLine: Decodable, Identifiable, Equatable, Sendable {
    let productId: Int
    let name: String
    let quantity: Double
    let amount: Double
    let bonus: Bool

    var id: String { "\(productId)/\(name)" }

    enum CodingKeys: String, CodingKey { case productId, name, quantity, amount, bonus }

    init(productId: Int = 0, name: String, quantity: Double = 1, amount: Double, bonus: Bool = false) {
        self.productId = productId
        self.name = name
        self.quantity = quantity
        self.amount = amount
        self.bonus = bonus
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        productId = c.lenientInt(.productId) ?? 0
        name = c.lenient(String.self, .name) ?? ""
        quantity = c.lenient(Double.self, .quantity) ?? 1
        amount = c.lenient(Double.self, .amount) ?? 0
        bonus = c.lenient(Bool.self, .bonus) ?? false
    }
}

struct SpendCategory: Decodable, Identifiable, Equatable, Sendable {
    let category: String
    let amount: Double

    var id: String { category }

    enum CodingKeys: String, CodingKey { case category, amount }

    init(category: String, amount: Double) {
        self.category = category
        self.amount = amount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        category = c.lenient(String.self, .category) ?? "Overig"
        amount = c.lenient(Double.self, .amount) ?? 0
    }
}

struct SpendTrip: Decodable, Identifiable, Equatable, Sendable {
    let id: Int
    let source: String
    let date: String
    let total: Double?
    let discount: Double?

    enum CodingKeys: String, CodingKey { case id, source, date, total, discount }

    init(id: Int, source: String, date: String, total: Double? = nil, discount: Double? = nil) {
        self.id = id
        self.source = source
        self.date = date
        self.total = total
        self.discount = discount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenientInt(.id) ?? 0
        source = c.lenient(String.self, .source) ?? ""
        date = c.lenient(String.self, .date) ?? ""
        total = c.lenient(Double.self, .total)
        discount = c.lenient(Double.self, .discount)
    }
}

struct SpendDetail: Decodable, Equatable, Sendable {
    let week: String
    let trips: [SpendTrip]
    let top: [SpendLine]
    let categories: [SpendCategory]

    enum CodingKeys: String, CodingKey { case week, trips, top, categories }

    init(week: String, trips: [SpendTrip] = [], top: [SpendLine] = [], categories: [SpendCategory] = []) {
        self.week = week
        self.trips = trips
        self.top = top
        self.categories = categories
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        week = c.lenient(String.self, .week) ?? ""
        trips = c.lenient([SpendTrip].self, .trips) ?? []
        top = c.lenient([SpendLine].self, .top) ?? []
        categories = c.lenient([SpendCategory].self, .categories) ?? []
    }
}

/// `GET /api/spend`
struct SpendResponse: Decodable, Equatable, Sendable {
    let weeks: [SpendWeek]
    let averageWeek: Double?
    let householdSize: Int
    let averagePerPersonDay: Double?
    let tripsTotal: Int
    let detail: SpendDetail?

    enum CodingKeys: String, CodingKey { case weeks, averageWeek, householdSize, averagePerPersonDay, tripsTotal, detail }

    init(weeks: [SpendWeek] = [], averageWeek: Double? = nil, householdSize: Int = 4, averagePerPersonDay: Double? = nil,
         tripsTotal: Int = 0, detail: SpendDetail? = nil) {
        self.weeks = weeks
        self.averageWeek = averageWeek
        self.householdSize = householdSize
        self.averagePerPersonDay = averagePerPersonDay
        self.tripsTotal = tripsTotal
        self.detail = detail
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        weeks = c.lenient([SpendWeek].self, .weeks) ?? []
        averageWeek = c.lenient(Double.self, .averageWeek)
        householdSize = c.lenientInt(.householdSize) ?? 4
        averagePerPersonDay = c.lenient(Double.self, .averagePerPersonDay)
        tripsTotal = c.lenientInt(.tripsTotal) ?? 0
        detail = c.lenient(SpendDetail.self, .detail)
    }
}

/// Eén product uit `GET /api/replenish` ("waarschijnlijk op").
struct ReplenishItem: Decodable, Identifiable, Equatable, Sendable {
    let productId: Int
    let name: String
    /// "op" (over tijd) of "binnenkort" (binnen een week).
    let status: String
    let intervalDays: Int
    let lastBought: String
    let daysLeft: Int
    let avgQuantity: Double
    /// Basisvoorraad uit de recepten (olie, bloem): al na twee aankopen voorgesteld.
    let basis: Bool

    var id: Int { productId }
    var isOverdue: Bool { status == "op" }

    enum CodingKeys: String, CodingKey { case productId, name, status, intervalDays, lastBought, daysLeft, avgQuantity, basis }

    init(productId: Int, name: String, status: String = "op", intervalDays: Int = 7, lastBought: String = "",
         daysLeft: Int = 0, avgQuantity: Double = 1, basis: Bool = false) {
        self.basis = basis
        self.productId = productId
        self.name = name
        self.status = status
        self.intervalDays = intervalDays
        self.lastBought = lastBought
        self.daysLeft = daysLeft
        self.avgQuantity = avgQuantity
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        productId = try c.decode(Int.self, forKey: .productId)
        name = c.lenient(String.self, .name) ?? "Product \(productId)"
        status = c.lenient(String.self, .status) ?? "op"
        intervalDays = c.lenientInt(.intervalDays) ?? 7
        lastBought = c.lenient(String.self, .lastBought) ?? ""
        daysLeft = c.lenientInt(.daysLeft) ?? 0
        avgQuantity = c.lenient(Double.self, .avgQuantity) ?? 1
        basis = c.lenient(Bool.self, .basis) ?? false
    }

    /// Hoeveel er op het lijstje gaat: het gebruikelijke aantal, minimaal 1.
    var quantity: Int { max(1, Int(avgQuantity.rounded())) }

    /// "waarschijnlijk op" / "over 3 dagen op"
    var whenText: String {
        isOverdue ? "waarschijnlijk op" : "over \(plural(max(daysLeft, 1), "dag", "dagen")) op"
    }
}

struct ReplenishResponse: Decodable, Equatable, Sendable {
    let due: [ReplenishItem]

    enum CodingKeys: String, CodingKey { case due }

    init(due: [ReplenishItem] = []) { self.due = due }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        due = c.lenient([ReplenishItem].self, .due) ?? []
    }
}

/// Antwoord met `ok` en eventueel een Nederlandse foutmelding (AH-fouten komen als HTTP 200 met `ok: false`).
struct InsightResult: Decodable, Sendable {
    let ok: Bool
    let error: String?
    let added: Int?
}

// MARK: Request-bodies

struct ExtrasProduct: Encodable, Equatable, Sendable {
    let productId: Int
    let name: String
    let quantity: Int

    enum CodingKeys: String, CodingKey {
        case name, quantity
        case productId = "product_id"
    }
}

struct ExtrasBody: Encodable, Equatable {
    var listIds: [String] = []
    var products: [ExtrasProduct]

    enum CodingKeys: String, CodingKey {
        case products
        case listIds = "list_ids"
    }
}

struct SnoozeBody: Encodable, Equatable {
    let productId: Int
    let days: Int

    enum CodingKeys: String, CodingKey {
        case days
        case productId = "product_id"
    }
}

struct OutBody: Encodable, Equatable {
    let productId: Int
    let name: String
    let quantity: Int

    enum CodingKeys: String, CodingKey {
        case name, quantity
        case productId = "product_id"
    }
}
