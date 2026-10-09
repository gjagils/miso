import Foundation

/// Body voor `PATCH /api/plan/settings` (beide optioneel).
struct PlanSettingsPatchBody: Encodable {
    var householdSize: Int?
    var orderWeekday: Int?

    enum CodingKeys: String, CodingKey {
        case householdSize = "household_size"
        case orderWeekday = "order_weekday"
    }
}
