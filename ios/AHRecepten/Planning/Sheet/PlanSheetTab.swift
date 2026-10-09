import Foundation

/// Tabbladen in het Inplannen-scherm vanuit het weekmenu.
enum PlanSheetTab: String, CaseIterable, Identifiable {
    case recipe
    case stock

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recipe: "Recept"
        case .stock: "Uit de vriezer / hebben we al"
        }
    }
}
