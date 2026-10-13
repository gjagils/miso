import SwiftUI

/// Regel met de geschatte kosten van een recept ("Ongeveer € 6,00 voor 4 (€ 1,50 p.p.)"). Toont niets zonder prijzen.
/// Een pure weergave: het scherm laadt de kosten (zie `RecipeDetailView.load`).
struct RecipeCostLine: View {
    let cost: RecipeCost?

    var body: some View {
        if let cost, cost.isUsable {
            Label(cost.summary, systemImage: "eurosign.circle")
                .font(.misoCaption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Regel met de geschatte kosten van de week (onder Boodschappen), met een balkje als er een weekbudget is.
struct WeekCostLine: View {
    let cost: WeekCost?

    var body: some View {
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
            .accessibilityElement(children: .combine)
        }
    }
}
