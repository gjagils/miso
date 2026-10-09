import SwiftUI

/// Dagkaart op Vandaag: recepten (tikbaar), restjes en "hebben we al".
struct OverviewDayCard: View {
    let day: PlanDay
    let items: [PlanItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(day.label).font(.misoHeadline).foregroundStyle(Color.misoBlue)
                if day.today { Text("vandaag").misoChip(.misoOrange) }
                Spacer()
            }
            if items.isEmpty {
                Text("Niets gepland").font(.misoBody).foregroundStyle(.secondary)
            }
            ForEach(items) { item in
                if let recipe = item.recipe, item.kind == .recipe {
                    NavigationLink(value: recipe) {
                        HStack {
                            PlanItemRow(item: item, persons: item.persons)
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary).accessibilityHidden(true)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                } else {
                    PlanItemRow(item: item, persons: item.persons)
                }
            }
        }
        .misoCard()
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.misoOrange, lineWidth: day.today ? 2 : 0)
        }
    }
}
