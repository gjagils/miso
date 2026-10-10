import Foundation
import Observation

/// Ontbrekend: open ingrediënten over alle recepten, per zoekterm een product kiezen of "Niet nodig".
@MainActor
@Observable
final class MissingModel {
    private(set) var groups: [MissingGroup] = []
    private(set) var totals: CoverageTotals?
    private(set) var loaded = false
    var errorText: String?
    /// Groep waarvoor nu een keuze naar de server gaat.
    private(set) var busyTerm: String?

    init(groups: [MissingGroup] = [], totals: CoverageTotals? = nil) {
        self.groups = groups
        self.totals = totals
        loaded = !groups.isEmpty
    }

    var lineCount: Int { groups.reduce(0) { $0 + $1.lines.count } }

    /// Alleen de recepten van deze week (maandag); nil = alle recepten.
    var week: String?

    func load(api: API) async {
        do {
            let result = try await api.missing(week: week)
            groups = result.groups
            totals = result.totaal
            errorText = nil
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            errorText = error.localizedDescription
        }
        loaded = true
    }

    /// Product kiezen (`product`) of niet nodig (`nil`) voor alle regels van de groep. Geeft true als het gelukt is.
    func assign(_ group: MissingGroup, product: AHProduct?, api: API) async -> Bool {
        busyTerm = group.term
        defer { busyTerm = nil }
        do {
            let result = try await api.assignMissing(lines: group.lines, product: product)
            guard result.ok else {
                errorText = result.error ?? "Opslaan is niet gelukt."
                return false
            }
            apply(result, for: group)
            if result.updated == 0 {
                // Recepten waren intussen gewijzigd: de server paste niets aan. Lijst verversen.
                errorText = "De recepten waren intussen gewijzigd. De lijst is ververst."
                await load(api: api)
                return false
            }
            errorText = nil
            return true
        } catch {
            errorText = "\(group.term): \(error.localizedDescription)"
            return false
        }
    }

    /// Groep uit de lijst halen en de totalen bijwerken (na een geslaagde keuze).
    func apply(_ result: MissingAssignResponse, for group: MissingGroup) {
        if let totaal = result.totaal { totals = totaal }
        groups.removeAll { $0.term == group.term }
    }
}
