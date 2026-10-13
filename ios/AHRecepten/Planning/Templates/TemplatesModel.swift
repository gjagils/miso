import Foundation
import Observation

/// Weeksjablonen: een week bewaren en terugzetten op een andere week. Bestelt niets.
@MainActor
@Observable
final class TemplatesModel {
    private(set) var templates: [WeekTemplate] = []
    private(set) var loaded = false
    private(set) var busy = false
    var newName = ""
    var errorText: String?
    var message: String?

    var canSave: Bool { !newName.trimmingCharacters(in: .whitespaces).isEmpty && !busy }

    func load(api: API) async {
        do {
            let response: TemplateListResponse = try await api.get("api/plan/templates")
            templates = response.templates
            errorText = nil
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            errorText = error.localizedDescription
        }
        loaded = true
    }

    func save(week: String, api: API) async {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        busy = true
        defer { busy = false }
        do {
            let result: TemplateSaveResponse = try await api.post("api/plan/templates",
                                                                  json: TemplateSaveBody(name: name, week: week))
            guard result.ok else {
                errorText = result.error ?? "Bewaren mislukt."
                return
            }
            newName = ""
            message = "\"\(name)\" bewaard."
            errorText = nil
            await load(api: api)
        } catch {
            errorText = "Bewaren mislukt. \(error.localizedDescription)"
        }
    }

    /// Zet het sjabloon op `week`. Bezette dagen blijven staan tenzij `replace`. Geeft true bij succes.
    func apply(_ template: WeekTemplate, week: String, replace: Bool, api: API) async -> Bool {
        busy = true
        defer { busy = false }
        do {
            let result: TemplateApplyResponse = try await api.post(
                "api/plan/templates/\(template.id)/apply", json: TemplateApplyBody(week: week, replace: replace))
            guard result.ok else {
                errorText = result.error ?? "Terugzetten mislukt."
                return false
            }
            message = result.summary
            errorText = nil
            return true
        } catch {
            errorText = "Terugzetten mislukt. \(error.localizedDescription)"
            return false
        }
    }

    func remove(_ template: WeekTemplate, api: API) async {
        do {
            let _: OKResponse = try await api.delete("api/plan/templates/\(template.id)")
            await load(api: api)
        } catch {
            errorText = "Weggooien mislukt. \(error.localizedDescription)"
        }
    }
}

struct TemplateSaveBody: Encodable {
    let name: String
    let week: String
}

struct TemplateApplyBody: Encodable {
    let week: String
    let replace: Bool
}
