import SwiftUI

/// Het gekozen recept, met "Ander recept" als er gezocht kan worden.
struct PlanChosenRecipeRow: View {
    let choice: PlanRecipeChoice
    var onChange: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            RecipeImage(path: choice.imageUrl, size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(choice.name)
                    .font(.system(.body, design: .rounded).weight(.bold))
                    .foregroundStyle(Color.misoBlue)
                if !choice.meta.isEmpty {
                    Text(choice.meta).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if let onChange {
                Button("Ander recept", action: onChange)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color.misoBlue)
                    .buttonStyle(.borderless)
                    .frame(minHeight: 44)
            }
        }
        .misoCard(padding: 12)
    }
}
