import Foundation

/// Navigatie binnen het weekmenu.
enum PlanRoute: Hashable {
    case recipe(Int)
    case freezer
    case templates
    case vote
    case missing
}
