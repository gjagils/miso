import Foundation
import Observation

@Observable
@MainActor
final class KiezenModel {
    var picked: [PickItem] = []
    /// Maandag van de gekozen week (leeg = huidige week, de server bepaalt).
    var week = ""

    func isPicked(_ key: String) -> Bool { picked.contains { $0.key == key } }

    func toggle(_ item: PickItem) {
        if let i = picked.firstIndex(where: { $0.key == item.key }) {
            picked.remove(at: i)
        } else {
            picked.append(item)
        }
    }

    var ownIDs: [Int] { picked.filter { $0.kind == .own }.map(\.recipeID) }

    /// Gekozen Allerhande-recepten eerst in de eigen bibliotheek zetten (POST /api/allerhande/add, form recipe_id).
    /// Geeft de mislukte recepten terug als "naam: fout".
    func importAllerhande(api: API, progress: @escaping @MainActor (Int, Int) -> Void) async -> [String] {
        let todo = picked.filter { $0.kind == .ah }
        guard !todo.isEmpty else { return [] }
        var done = 0
        var failed: [String] = []
        progress(0, todo.count)
        await withTaskGroup(of: (PickItem, Result<Int, Error>).self) { group in
            for item in todo {
                group.addTask {
                    do {
                        let r = try await api.addAllerhande(id: item.recipeID)
                        if r.ok, let id = r.id { return (item, .success(id)) }
                        return (item, .failure(APIError(message: r.error ?? "mislukt")))
                    } catch {
                        return (item, .failure(error))
                    }
                }
            }
            for await (item, result) in group {
                done += 1
                progress(done, todo.count)
                switch result {
                case .success(let id):
                    let own = PickItem(key: "own:\(id)", kind: .own, recipeID: id, name: item.name,
                                       imageUrl: item.imageUrl, meta: item.meta)
                    if let i = picked.firstIndex(where: { $0.key == item.key }) {
                        if isPicked(own.key) { picked.remove(at: i) } else { picked[i] = own }
                    }
                case .failure(let error):
                    failed.append("\(item.name): \(error.localizedDescription)")
                }
            }
        }
        return failed
    }

    func reset() {
        picked = []
        week = ""
    }
}
