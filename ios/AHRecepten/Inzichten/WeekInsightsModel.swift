import Foundation
import Observation

/// Kosten van de week en "waarschijnlijk op" voor het weekmenu. Wordt door het scherm zelf geladen (niet door de
/// weergaven): een `.task` op een weergave die nog niets toont (lege `Group`) draait in SwiftUI niet.
@MainActor
@Observable
final class WeekInsightsModel {
    private(set) var cost: WeekCost?
    let replenish = ReplenishModel()

    func load(week: String, api: API) async {
        // Oudere server of AH niet gekoppeld: gewoon niets tonen.
        cost = try? await api.weekCost(week)
        await replenish.load(week: week, api: api)
    }
}
