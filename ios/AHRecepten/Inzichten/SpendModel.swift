import Foundation
import Observation

/// Uitgavenoverzicht: per week uit de AH-datalaag (bestellingen en kassabonnen).
@MainActor
@Observable
final class SpendModel {
    private(set) var spend: SpendResponse?
    private(set) var loaded = false
    private(set) var syncing = false
    private(set) var selectedWeek: String?
    var errorText: String?
    var message: String?

    var detail: SpendDetail? { spend?.detail }

    func load(api: API, detail: String? = nil) async {
        do {
            spend = try await api.spend(detail: detail ?? selectedWeek)
            errorText = nil
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            errorText = "Uitgaven ophalen mislukt. \(error.localizedDescription)"
        }
        loaded = true
    }

    func select(_ week: String, api: API) async {
        selectedWeek = selectedWeek == week ? nil : week
        await load(api: api, detail: selectedWeek)
    }

    /// Nieuwe bestellingen en bonnen ophalen. Alleen lezen.
    func sync(api: API) async {
        syncing = true
        message = nil
        defer { syncing = false }
        do {
            let result = try await api.syncAHData()
            message = result.ok ? "\(result.added ?? 0) nieuwe ritten opgehaald." : (result.error ?? "Bijwerken is mislukt.")
            if result.ok { await load(api: api) }
        } catch {
            message = "Bijwerken is mislukt. \(error.localizedDescription)"
        }
    }
}
