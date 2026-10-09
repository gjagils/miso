import Foundation
import Observation

/// Weekmenu: planregels per dag, gezondheid, boodschappen-status en de acties daarop.
@MainActor
@Observable
final class WeekPlanModel {
    private(set) var week: WeekResponse?
    private(set) var health: WeekHealth?
    var errorText: String?
    private(set) var pushing = false
    /// Uitkomst van "Zet N nieuwe producten op je AH-lijstje".
    private(set) var pushResult: (ok: Bool, text: String)?
    /// Personen die net zijn aangepast en nog naar de server gaan (entry_id -> aantal).
    private(set) var pendingPersons: [Int: Int] = [:]
    private var personsTasks: [Int: Task<Void, Never>] = [:]

    var household: Int { week?.householdSize ?? 4 }

    func items(for day: PlanDay) -> [PlanItem] {
        day.planItems(householdSize: household)
    }

    func persons(for item: PlanItem) -> Int {
        item.entryId.flatMap { pendingPersons[$0] } ?? (item.persons > 0 ? item.persons : household)
    }

    func profile(for item: PlanItem) -> HealthProfile? {
        guard let id = item.entryId else { return nil }
        return health?.profilesByEntry[id]
    }

    /// Eerste vrije dag vanaf vandaag in deze week (voor "Plan in" vanuit de vriezer).
    var firstFreeDay: String? {
        guard let week else { return nil }
        let entries = week.days.flatMap(items(for:))
        return DayChipBuilder.firstFreeDay(week: week.week, today: KiezenDates.today, entries: entries)
    }

    // MARK: Laden

    func load(api: API, week start: String?) async {
        do {
            let result = try await api.week(start ?? week?.week)
            if result.week != week?.week { health = nil }
            week = result
            errorText = nil
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            // Staat er al een weekmenu, dan blijft dat staan en komt de fout in een melding erboven.
            errorText = error.localizedDescription
            return
        }
        await loadHealth(api: api)
    }

    /// Gezondheid kan even duren (Claude schat ontbrekende profielen); de dagen staan dan al.
    func loadHealth(api: API) async {
        guard let current = week?.week else { return }
        guard let result = try? await api.weekHealth(current), week?.week == current else { return }
        health = result
    }

    func showWeek(_ start: String, api: API) async {
        pushResult = nil
        await load(api: api, week: start)
    }

    // MARK: Planregels

    func delete(_ item: PlanItem, api: API) async {
        guard let id = item.entryId else { return }
        do {
            _ = try await api.deletePlanEntry(id)
            await afterChange(api: api)
        } catch {
            errorText = "Verwijderen mislukt. \(error.localizedDescription)"
        }
    }

    /// Personen aanpassen: direct tonen, na een korte pauze opslaan (zodat snel tikken één verzoek wordt).
    func setPersons(_ value: Int, for item: PlanItem, api: API) {
        guard let id = item.entryId else { return }
        pendingPersons[id] = value
        personsTasks[id]?.cancel()
        let household = household
        personsTasks[id] = Task {
            try? await Task.sleep(for: .milliseconds(600))
            if Task.isCancelled { return }
            do {
                _ = try await api.updatePlanEntry(id, PlanEntryPatchBody(persons: .from(value, household: household)))
                await afterChange(api: api)
            } catch {
                errorText = "Personen aanpassen mislukt. \(error.localizedDescription)"
            }
            if pendingPersons[id] == value { pendingPersons[id] = nil }
            personsTasks[id] = nil
        }
    }

    /// Na elke wijziging: week (status) opnieuw laden en de besteldag-herinnering bijwerken.
    func afterChange(api: API) async {
        pushResult = nil
        await load(api: api, week: week?.week)
        await OrderReminderScheduler.refresh(api: api)
    }

    // MARK: Boodschappen

    /// Zet de nieuwe producten van deze week op het AH-lijstje (zelfde call als de web-knop). Bestelt niets.
    func pushToList(api: API) async {
        guard let current = week?.week else { return }
        pushing = true
        defer { pushing = false }
        do {
            let result = try await api.pushWeekToList(current)
            if result.ok {
                let added = result.added ?? 0
                pushResult = (true, added > 0 ? "\(plural(added, "product", "producten")) op je AH-lijstje gezet."
                                              : "Alles stond al op je lijstje.")
            } else {
                pushResult = (false, result.error ?? "Het lijstje bijwerken is mislukt.")
            }
        } catch {
            pushResult = (false, error.localizedDescription)
        }
        let message = pushResult
        await load(api: api, week: current)
        pushResult = message
    }
}
