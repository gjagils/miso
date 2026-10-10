import Foundation
import Observation

/// Lijststatus van één week laden en "Zet ontbrekende op mijn AH-lijstje" (`POST /api/plan/sync`).
@MainActor
@Observable
final class ListStatusModel {
    private(set) var status: ListStatus?
    private(set) var syncing = false
    private(set) var checking = false
    private(set) var message: String?

    /// Laatst opgeslagen status (geen AH-check).
    func load(api: API, week: String) async {
        guard !week.isEmpty else { return }
        do {
            let result = try await api.listStatus(week: week)
            status = result.ok ? result : nil
        } catch {
            // Oudere server of kind (403): geen kaart.
            status = nil
        }
    }

    /// "Controleer met AH": één keer bij AH nakijken en opslaan.
    func check(api: API) async {
        guard let week = status?.week, !week.isEmpty else { return }
        checking = true
        defer { checking = false }
        do {
            let result = try await api.listStatus(week: week, check: true)
            if result.ok { status = result; message = nil } else { message = "Controleren lukte niet." }
        } catch {
            message = error.localizedDescription
        }
    }

    /// Na "Zet ontbrekende op mijn AH-lijstje" controleert de server zelf; daarna alleen opnieuw lezen.
    func sync(api: API) async {
        guard let week = status?.week, !week.isEmpty else { return }
        syncing = true
        defer { syncing = false }
        do {
            let result = try await api.pushWeekToList(week)
            if result.ok {
                let added = result.added ?? 0
                message = added > 0 ? "\(plural(added, "product", "producten")) op je AH-lijstje gezet."
                                    : "Alles stond al op je AH-lijstje."
            } else {
                message = result.error ?? "Bijwerken lukte niet."
            }
        } catch {
            message = error.localizedDescription
        }
        await load(api: api, week: week)
    }

    func reset() {
        status = nil
        message = nil
    }
}
