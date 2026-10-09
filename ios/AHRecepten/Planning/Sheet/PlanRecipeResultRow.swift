import SwiftUI

/// Zoekresultaat (eigen recept of Allerhande) in het Inplannen-scherm.
struct PlanRecipeResultRow: View {
    let choice: PlanRecipeChoice
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                RecipeImage(path: choice.imageUrl, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(choice.name)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(Color.misoBlue)
                        .multilineTextAlignment(.leading)
                    if !choice.meta.isEmpty {
                        Text(choice.meta).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "plus.circle").foregroundStyle(Color.misoOrange).accessibilityHidden(true)
            }
            .frame(minHeight: 52)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Kiest dit recept")
    }
}
