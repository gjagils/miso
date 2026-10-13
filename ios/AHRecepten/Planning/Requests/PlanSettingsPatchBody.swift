import Foundation

/// Body voor `PATCH /api/plan/settings` (beide optioneel).
struct PlanSettingsPatchBody: Encodable {
    var householdSize: Int?
    var orderWeekday: Int?
    var weekBudget: Int?
    /// 0-6, of -1 om de kids-kookavond uit te zetten.
    var kidsWeekday: Int?

    enum CodingKeys: String, CodingKey {
        case householdSize = "household_size"
        case orderWeekday = "order_weekday"
        case weekBudget = "week_budget"
        case kidsWeekday = "kids_weekday"
    }
}
