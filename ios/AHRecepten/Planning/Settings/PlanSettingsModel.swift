import Foundation
import Observation

/// Gezinsgrootte en besteldag (server-instellingen, gedeeld met de web-versie).
@MainActor
@Observable
final class PlanSettingsModel {
    private(set) var settings: PlanSettings?
    var errorText: String?
    private var saveTask: Task<Void, Never>?

    func load(api: API) async {
        do {
            settings = try await api.planSettings()
            errorText = nil
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            errorText = "Instellingen ophalen mislukt. \(error.localizedDescription)"
        }
    }

    /// Direct tonen, na een korte pauze opslaan (snel tikken = één verzoek).
    func setHouseholdSize(_ value: Int, api: API) {
        guard var current = settings else { return }
        current.householdSize = min(max(value, 1), 20)
        settings = current
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            if Task.isCancelled { return }
            await save(PlanSettingsPatchBody(householdSize: current.householdSize), api: api)
        }
    }

    /// Direct tonen, na een korte pauze opslaan (stappen van 10 euro).
    func setWeekBudget(_ value: Int, api: API) {
        guard var current = settings else { return }
        current.weekBudget = min(max(value, 0), 9999)
        settings = current
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            if Task.isCancelled { return }
            await save(PlanSettingsPatchBody(weekBudget: current.weekBudget), api: api)
        }
    }

    func setOrderWeekday(_ weekday: Int, api: API) async {
        guard var current = settings, current.orderWeekday != weekday else { return }
        current.orderWeekday = weekday
        current.orderWeekdayName = PlanSettings.name(of: weekday)
        settings = current
        await save(PlanSettingsPatchBody(orderWeekday: weekday), api: api)
        await OrderReminderScheduler.refresh(api: api)
    }

    /// nil = geen vaste kids-kookavond.
    func setKidsWeekday(_ weekday: Int?, api: API) async {
        guard var current = settings, current.kidsWeekday != weekday else { return }
        current.kidsWeekday = weekday
        settings = current
        await save(PlanSettingsPatchBody(kidsWeekday: weekday ?? -1), api: api)
    }

    private func save(_ body: PlanSettingsPatchBody, api: API) async {
        do {
            settings = try await api.updatePlanSettings(body)
            errorText = nil
        } catch {
            errorText = "Opslaan mislukt. \(error.localizedDescription)"
            await load(api: api)
        }
    }
}
