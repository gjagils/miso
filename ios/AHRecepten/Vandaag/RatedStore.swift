import Foundation

/// Welke gerechten dit gezinslid al "Lekker?" gaf (of wegklikte), per dag. De server stuurt dat niet mee,
/// dus de app onthoudt het op het toestel; zo vraagt "Gisteren: … Lekker?" het niet twee keer.
struct RatedStore {
    var defaults: UserDefaults = .standard
    private static let key = "ratedMeals"
    /// Ouder dan dit wordt opgeruimd.
    private static let keep = 60

    private func key(member: String, date: String, recipeID: Int) -> String {
        "\(member)|\(date)|\(recipeID)"
    }

    func isRated(recipeID: Int, date: String, member: String) -> Bool {
        (defaults.stringArray(forKey: Self.key) ?? []).contains(key(member: member, date: date, recipeID: recipeID))
    }

    func mark(recipeID: Int, date: String, member: String) {
        var all = defaults.stringArray(forKey: Self.key) ?? []
        let k = key(member: member, date: date, recipeID: recipeID)
        guard !all.contains(k) else { return }
        all.append(k)
        defaults.set(Array(all.suffix(Self.keep)), forKey: Self.key)
    }

    /// Vraag over gisteren nog stellen? Niet als het gisteren of vandaag al beoordeeld is.
    func shouldAsk(recipeID: Int, yesterday: String, today: String, member: String) -> Bool {
        !isRated(recipeID: recipeID, date: yesterday, member: member)
            && !isRated(recipeID: recipeID, date: today, member: member)
    }
}
