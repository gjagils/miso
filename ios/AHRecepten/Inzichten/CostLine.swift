import SwiftUI

/// Regel met de geschatte kosten van een recept ("Ongeveer € 6,00 voor 4 (€ 1,50 p.p.)"). Leeg zolang er geen prijzen zijn.
struct RecipeCostLine: View {
    @Environment(Session.self) private var session
    let recipeID: Int
    @State private var cost: RecipeCost?

    var body: some View {
        Group {
            if let cost, cost.isUsable {
                Label(cost.summary, systemImage: "eurosign.circle")
                    .font(.misoCaption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task(id: recipeID) {
            guard let api = session.api else { return }
            cost = try? await api.recipeCost(recipeID)
        }
    }
}

/// Regel met de geschatte kosten van de week (onder Boodschappen).
struct WeekCostLine: View {
    @Environment(Session.self) private var session
    let week: String
    /// Verandert er iets in de planning of op het lijstje, dan opnieuw rekenen.
    var version = 0
    @State private var cost: WeekCost?

    var body: some View {
        Group {
            if let cost, cost.isUsable {
                VStack(alignment: .leading, spacing: 6) {
                    Label(cost.summary, systemImage: "eurosign.circle")
                        .font(.callout)
                        .foregroundStyle(Color.misoBlue)
                    if let budgetText = cost.budgetText {
                        Text(budgetText).font(.misoCaption).foregroundStyle(.secondary)
                        GeometryReader { proxy in
                            Capsule().fill(Color.misoCream)
                                .overlay(alignment: .leading) {
                                    Capsule().fill(cost.overBudget ? Color.red : Color.misoOrange)
                                        .frame(width: proxy.size.width * min(1, Double(cost.budgetPct ?? 0) / 100))
                                }
                        }
                        .frame(height: 8)
                        .accessibilityHidden(true)
                    }
                }
            }
        }
        .task(id: "\(week)/\(version)") {
            guard let api = session.api else { return }
            cost = try? await api.weekCost(week)
        }
    }
}
