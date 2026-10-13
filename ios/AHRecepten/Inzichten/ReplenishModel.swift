import Foundation
import Observation

/// "Waarschijnlijk op" in het weekmenu: producten die volgens het koopritme aan de beurt zijn.
@MainActor
@Observable
final class ReplenishModel {
    private(set) var items: [ReplenishItem] = []
    private(set) var busyID: Int?
    private(set) var message: String?

    func load(week: String, api: API) async {
        // Een oudere server zonder dit endpoint, of AH niet gekoppeld: gewoon niets tonen.
        items = (try? await api.replenish(week: week)) ?? []
    }

    /// Op het AH-lijstje; daarna niet meteen opnieuw voorstellen (een interval lang rust).
    func addToList(_ item: ReplenishItem, week: String, api: API) async {
        busyID = item.productId
        defer { busyID = nil }
        do {
            let result = try await api.addToList([ExtrasProduct(productId: item.productId, name: item.name,
                                                                quantity: item.quantity)])
            guard result.ok else {
                message = result.error ?? "Op het lijstje zetten is mislukt."
                return
            }
            message = "\(item.name) staat op je AH-lijstje."
            _ = try? await api.snooze(productID: item.productId, days: max(item.intervalDays, 7))
            await load(week: week, api: api)
        } catch {
            message = "Op het lijstje zetten is mislukt. \(error.localizedDescription)"
        }
    }

    /// "Hebben we nog": de voorspelling schuift een halve interval op.
    func haveStill(_ item: ReplenishItem, week: String, api: API) async {
        busyID = item.productId
        defer { busyID = nil }
        _ = try? await api.snooze(productID: item.productId, days: max(7, item.intervalDays / 2))
        await load(week: week, api: api)
    }
}
