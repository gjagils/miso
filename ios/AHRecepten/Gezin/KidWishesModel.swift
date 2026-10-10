import Foundation
import Observation

/// "Wat wil jij graag eten?" voor een kind: wens typen, iets voor de boodschappen, favorieten als kaartjes,
/// wat al doorgegeven is en het menu (alleen lezen).
@MainActor
@Observable
final class KidWishesModel {
    private(set) var favorites: [RecipeSummary] = []
    /// Favorieten van de rest van het gezin: ook met één tik door te geven (handig als je zelf nog geen
    /// favorieten hebt).
    private(set) var familyFavorites: [RecipeSummary] = []
    private(set) var myWishes: [FamilyWish] = []
    private(set) var menu: [PlanItem] = []
    private(set) var loaded = false
    private(set) var sending = false
    private(set) var message: String?
    /// Favorieten waarvoor net een wens is doorgegeven ("✓ doorgegeven").
    private(set) var sentRecipeIDs: Set<Int> = []

    func load(api: API, me: Member?) async {
        async let favs = try? api.recipes(filter: .favorites)
        async let wishes = try? api.familyWishes()
        async let plan = try? api.planEntries(start: KiezenDates.today, days: 7)
        let allFavorites = await favs ?? []
        favorites = Self.mine(allFavorites, initial: me?.initial)
        familyFavorites = Self.others(allFavorites, initial: me?.initial)
        let all = await wishes ?? []
        myWishes = all.filter { $0.memberId == me?.id }
        sentRecipeIDs = Set(myWishes.compactMap(\.recipeId))
        menu = (await plan)?.entries ?? []
        loaded = true
    }

    /// Mijn favorieten (mijn initiaal bij de fans), zonder opgeruimde recepten.
    static func mine(_ recipes: [RecipeSummary], initial: String?) -> [RecipeSummary] {
        recipes.filter { r in
            !(r.archived ?? false) && (initial.map { (r.fans ?? []).contains($0) } ?? r.isFavorite)
        }
    }

    /// Favorieten van anderen in het gezin (meeste fans eerst), hooguit acht.
    static func others(_ recipes: [RecipeSummary], initial: String?) -> [RecipeSummary] {
        guard let initial else { return [] }
        let list = recipes.filter { r in
            !(r.archived ?? false) && !(r.fans ?? []).isEmpty && !(r.fans ?? []).contains(initial)
        }
        return Array(list.sorted { ($0.fans?.count ?? 0) > ($1.fans?.count ?? 0) }.prefix(8))
    }

    /// Geeft true als het doorgegeven is.
    func send(_ body: WishBody, api: API, me: Member?) async -> Bool {
        sending = true
        defer { sending = false }
        do {
            let result = try await api.addWish(body)
            guard result.ok else {
                message = result.error ?? "Dat lukte niet."
                return false
            }
            myWishes = result.wishes.filter { $0.memberId == me?.id }
            if let id = body.recipeId { sentRecipeIDs.insert(id) }
            message = body.kind == .boodschap ? "Staat op het wensenlijstje voor de boodschappen! 🛒"
                                              : "Doorgegeven! 🎉 Papa en mama zien het bij het plannen."
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    func withdraw(_ wish: FamilyWish, api: API, me: Member?) async {
        do {
            let result = try await api.deleteWish(wish.id)
            myWishes = result.wishes.filter { $0.memberId == me?.id }
            if let id = wish.recipeId { sentRecipeIDs.remove(id) }
        } catch {
            message = error.localizedDescription
        }
    }

    /// Menu per dag, vandaag en de zes dagen erna.
    var days: [(date: String, items: [PlanItem])] {
        (0..<7).map { offset in
            let date = KiezenDates.add(KiezenDates.today, offset)
            return (date, menu.filter { $0.date == date })
        }
    }
}
