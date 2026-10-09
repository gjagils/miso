import Foundation

/// Gezinsgrootte en besteldag (`GET/PATCH /api/plan/settings`).
struct PlanSettings: Decodable, Equatable, Sendable {
    var householdSize: Int
    /// 0 = maandag … 6 = zondag.
    var orderWeekday: Int
    var orderWeekdayName: String

    static let weekdayNames = ["maandag", "dinsdag", "woensdag", "donderdag", "vrijdag", "zaterdag", "zondag"]

    enum CodingKeys: String, CodingKey { case householdSize, orderWeekday, orderWeekdayName }

    init(householdSize: Int = 4, orderWeekday: Int = 6, orderWeekdayName: String? = nil) {
        self.householdSize = householdSize
        self.orderWeekday = orderWeekday
        self.orderWeekdayName = orderWeekdayName ?? Self.name(of: orderWeekday)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let weekday = c.lenientInt(.orderWeekday) ?? 6
        self.init(householdSize: c.lenientInt(.householdSize) ?? 4,
                  orderWeekday: weekday,
                  orderWeekdayName: c.lenient(String.self, .orderWeekdayName))
    }

    static func name(of weekday: Int) -> String {
        weekdayNames.indices.contains(weekday) ? weekdayNames[weekday] : ""
    }
}
