import Foundation
import Observation

/// Vriezerlijst: wat erin ligt en hoeveel porties.
@MainActor
@Observable
final class FreezerModel {
    private(set) var items: [FreezerItem] = []
    private(set) var loaded = false
    var errorText: String?
    var newName = ""
    var newPortions = 4
    private(set) var adding = false
    private var portionsTouched = false

    var canAdd: Bool { !newName.trimmingCharacters(in: .whitespaces).isEmpty && !adding }

    func load(api: API) async {
        if !portionsTouched, let settings = try? await api.planSettings() {
            newPortions = settings.householdSize
        }
        do {
            items = try await api.freezerItems()
            errorText = nil
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            errorText = error.localizedDescription
        }
        loaded = true
    }

    func setNewPortions(_ value: Int) {
        newPortions = value
        portionsTouched = true
    }

    func add(api: API) async {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        adding = true
        defer { adding = false }
        do {
            let result = try await api.addFreezerItem(name: name, portions: newPortions)
            guard result.ok else {
                errorText = "Toevoegen mislukt."
                return
            }
            newName = ""
            await load(api: api)
        } catch {
            errorText = "Toevoegen mislukt. \(error.localizedDescription)"
        }
    }

    /// Eén portie minder; bij 0 haalt de server het item weg.
    func decrement(_ item: FreezerItem, api: API) async {
        do {
            _ = try await api.setFreezerPortions(item.id, portions: item.portions - 1)
            await load(api: api)
        } catch {
            errorText = "Aanpassen mislukt. \(error.localizedDescription)"
        }
    }

    func remove(_ item: FreezerItem, api: API) async {
        do {
            try await api.deleteFreezerItem(item.id)
            await load(api: api)
        } catch {
            errorText = "Weghalen mislukt. \(error.localizedDescription)"
        }
    }
}
