import Foundation

/// Gezinsgrootte en besteldag (`GET/PATCH /api/plan/settings`).
struct PlanSettings: Decodable, Equatable, Sendable {
    var householdSize: Int
    /// 0 = maandag … 6 = zondag.
    var orderWeekday: Int
    var orderWeekdayName: String
    /// Euro's per week voor de boodschappen; 0 = geen budget.
    var weekBudget: Int = 0
    /// Vaste kids-kookavond: 0 = maandag … 6 = zondag; nil = geen.
    var kidsWeekday: Int? = nil

    static let weekdayNames = ["maandag", "dinsdag", "woensdag", "donderdag", "vrijdag", "zaterdag", "zondag"]

    enum CodingKeys: String, CodingKey { case householdSize, orderWeekday, orderWeekdayName, weekBudget, kidsWeekday }

    init(householdSize: Int = 4, orderWeekday: Int = 6, orderWeekdayName: String? = nil, weekBudget: Int = 0,
         kidsWeekday: Int? = nil) {
        self.weekBudget = weekBudget
        self.kidsWeekday = kidsWeekday
        self.householdSize = householdSize
        self.orderWeekday = orderWeekday
        self.orderWeekdayName = orderWeekdayName ?? Self.name(of: orderWeekday)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let weekday = c.lenientInt(.orderWeekday) ?? 6
        self.init(householdSize: c.lenientInt(.householdSize) ?? 4,
                  orderWeekday: weekday,
                  orderWeekdayName: c.lenient(String.self, .orderWeekdayName),
                  weekBudget: c.lenientInt(.weekBudget) ?? 0,
                  kidsWeekday: c.lenientInt(.kidsWeekday))
    }

    static func name(of weekday: Int) -> String {
        weekdayNames.indices.contains(weekday) ? weekdayNames[weekday] : ""
    }
}
