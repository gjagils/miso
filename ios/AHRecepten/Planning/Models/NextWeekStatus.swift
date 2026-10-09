import Foundation

/// `GET /api/plan/next-week-status`: hoe ver volgende week gepland is en hoe lang tot de besteldag.
struct NextWeekStatus: Decodable, Equatable, Sendable {
    let orderDay: Int
    let orderDayName: String
    /// 0 = vandaag is de besteldag.
    let daysUntilOrder: Int
    /// Maandag van volgende week.
    let week: String
    let plannedDays: Int
    let totalDays: Int
    let missingDates: [String]
    /// Groot tonen (vanaf 2 dagen voor de besteldag).
    let prominent: Bool
    let message: String
    let listStatus: NextWeekListStatus?

    enum CodingKeys: String, CodingKey {
        case orderDay, orderDayName, daysUntilOrder, week, plannedDays, totalDays, missingDates, prominent, message
        case listStatus
    }

    init(orderDay: Int = 6, orderDayName: String = "zondag", daysUntilOrder: Int, week: String, plannedDays: Int,
         totalDays: Int = 7, missingDates: [String] = [], prominent: Bool = false, message: String = "",
         listStatus: NextWeekListStatus? = nil) {
        self.orderDay = orderDay
        self.orderDayName = orderDayName
        self.daysUntilOrder = daysUntilOrder
        self.week = week
        self.plannedDays = plannedDays
        self.totalDays = totalDays
        self.missingDates = missingDates
        self.prominent = prominent
        self.message = message
        self.listStatus = listStatus
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        orderDay = c.lenientInt(.orderDay) ?? 6
        orderDayName = c.lenient(String.self, .orderDayName) ?? PlanSettings.name(of: orderDay)
        daysUntilOrder = c.lenientInt(.daysUntilOrder) ?? 0
        week = c.lenient(String.self, .week) ?? ""
        plannedDays = c.lenientInt(.plannedDays) ?? 0
        totalDays = c.lenientInt(.totalDays) ?? 7
        missingDates = c.lenient([String].self, .missingDates) ?? []
        prominent = c.lenient(Bool.self, .prominent) ?? (daysUntilOrder <= 2)
        message = c.lenient(String.self, .message) ?? ""
        listStatus = c.lenient(NextWeekListStatus.self, .listStatus)
    }

    var isComplete: Bool { plannedDays >= totalDays }
}
