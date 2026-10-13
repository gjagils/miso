import Foundation

/// Eén dag in een opgeslagen week: weekdag (0 = maandag) en wat er stond.
struct TemplateDay: Decodable, Hashable, Sendable {
    let weekday: Int
    let label: String
    /// Het recept bestaat niet meer; dat wordt bij terugzetten overgeslagen.
    let missing: Bool

    enum CodingKeys: String, CodingKey { case weekday, label, missing }

    init(weekday: Int, label: String, missing: Bool = false) {
        self.weekday = weekday
        self.label = label
        self.missing = missing
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(weekday: c.lenientInt(.weekday) ?? 0,
                  label: c.lenient(String.self, .label) ?? "",
                  missing: c.lenient(Bool.self, .missing) ?? false)
    }
}

/// Een bewaarde week ("Standaardweek"), `GET /api/plan/templates`.
struct WeekTemplate: Decodable, Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let createdOn: String?
    let count: Int
    let days: [TemplateDay]

    enum CodingKeys: String, CodingKey { case id, name, createdOn, count, days }

    init(id: Int, name: String, createdOn: String? = nil, count: Int = 0, days: [TemplateDay] = []) {
        self.id = id
        self.name = name
        self.createdOn = createdOn
        self.count = count
        self.days = days
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.lenientInt(.id) else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "sjabloon zonder id")
        }
        let days = c.lenient([TemplateDay].self, .days) ?? []
        self.init(id: id, name: c.lenient(String.self, .name) ?? "", createdOn: c.lenient(String.self, .createdOn),
                  count: c.lenientInt(.count) ?? days.count, days: days)
    }

    /// "ma Lasagne · wo Pasta": korte samenvatting onder de naam.
    var summary: String {
        let short = ["ma", "di", "wo", "do", "vr", "za", "zo"]
        return days.sorted { $0.weekday < $1.weekday }
            .map { "\(short[min(max($0.weekday, 0), 6)]) \($0.label)" }
            .joined(separator: " · ")
    }
}

struct TemplateListResponse: Decodable, Sendable {
    let templates: [WeekTemplate]

    enum CodingKeys: String, CodingKey { case templates }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        templates = c.lenient([WeekTemplate].self, .templates) ?? []
    }
}

/// `POST /api/plan/templates`: ok, of een foutmelding ("Deze week is nog leeg ...").
struct TemplateSaveResponse: Decodable, Sendable {
    let ok: Bool
    let error: String?
    let template: WeekTemplate?

    enum CodingKeys: String, CodingKey { case ok, error, template }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = c.lenient(Bool.self, .ok) ?? false
        error = c.lenient(String.self, .error)
        template = c.lenient(WeekTemplate.self, .template)
    }
}

/// `POST /api/plan/templates/{id}/apply`.
struct TemplateApplyResponse: Decodable, Sendable {
    let ok: Bool
    let error: String?
    let placed: Int
    let skippedBusy: Int
    let skippedGone: Int

    enum CodingKeys: String, CodingKey { case ok, error, placed, skippedBusy, skippedGone }

    init(ok: Bool = true, error: String? = nil, placed: Int, skippedBusy: Int = 0, skippedGone: Int = 0) {
        self.ok = ok
        self.error = error
        self.placed = placed
        self.skippedBusy = skippedBusy
        self.skippedGone = skippedGone
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(ok: c.lenient(Bool.self, .ok) ?? false, error: c.lenient(String.self, .error),
                  placed: c.lenientInt(.placed) ?? 0, skippedBusy: c.lenientInt(.skippedBusy) ?? 0,
                  skippedGone: c.lenientInt(.skippedGone) ?? 0)
    }

    /// "3 dagen gevuld, 1 bezette dag overgeslagen."
    var summary: String {
        func plural(_ n: Int, _ one: String, _ more: String) -> String { "\(n) \(n == 1 ? one : more)" }
        var bits = ["\(plural(placed, "dag", "dagen")) gevuld"]
        if skippedBusy > 0 { bits.append("\(plural(skippedBusy, "bezette dag", "bezette dagen")) overgeslagen") }
        if skippedGone > 0 { bits.append("\(plural(skippedGone, "verwijderd recept", "verwijderde recepten")) overgeslagen") }
        return bits.joined(separator: ", ") + "."
    }
}
