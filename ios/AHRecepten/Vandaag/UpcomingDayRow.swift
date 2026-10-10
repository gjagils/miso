import SwiftUI

/// Morgen / overmorgen, klein onder het gerecht van vandaag.
struct UpcomingDayRow: View {
    let title: String
    let items: [PlanItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            if items.isEmpty {
                Text("Nog niets gepland").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(items) { item in
                if let recipe = item.recipe, item.kind == .recipe {
                    NavigationLink(value: recipe) {
                        row(item)
                    }
                    .buttonStyle(.plain)
                } else {
                    row(item)
                }
            }
        }
        .misoCard(padding: 12)
    }

    private func row(_ item: PlanItem) -> some View {
        HStack(spacing: 10) {
            PlanItemThumbnail(item: item, size: 44)
            Text(item.title)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(Color.misoBlue)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            if item.kind == .recipe {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 44)
        .contentShape(.rect)
    }
}
