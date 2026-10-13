import Foundation
import Observation

/// Kosten van de week, "waarschijnlijk op" en "koken met wat er is" voor het weekmenu. Wordt door het scherm zelf geladen (niet door de
/// weergaven): een `.task` op een weergave die nog niets toont (lege `Group`) draait in SwiftUI niet.
@MainActor
@Observable
final class WeekInsightsModel {
    private(set) var cost: WeekCost?
    private(set) var cookWith: [CookWithSuggestion] = []
    let replenish = ReplenishModel()

    func load(week: String, api: API) async {
        // Oudere server of AH niet gekoppeld: gewoon niets tonen.
        cost = try? await api.weekCost(week)
        cookWith = (try? await api.cookWith()) ?? []
        await replenish.load(week: week, api: api)
    }
}
