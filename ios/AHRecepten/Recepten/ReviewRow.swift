import SwiftUI

/// Rij op het Opruimen-scherm: foto, naam, reden + gebruik, en drie knoppen.
struct ReviewRow: View {
    let recipe: ReviewRecipe
    let busy: Bool
    let onKeep: () -> Void
    let onByHeart: () -> Void
    let onArchive: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink(value: RecipeSummaryLink(id: recipe.id)) {
                HStack(spacing: 12) {
                    RecipeImage(path: recipe.imageUrl, size: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(recipe.name)
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .foregroundStyle(Color.misoBlue)
                        Text(recipe.statsLine)
                            .font(.misoCaption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            FlowLayout(spacing: 8) {
                action("Bewaren", systemImage: "hand.thumbsup", action: onKeep,
                       hint: "Een half jaar niet meer vragen")
                if !recipe.byHeart {
                    action("Uit mijn hoofd", systemImage: "brain.head.profile", action: onByHeart,
                           hint: "Houdt de boodschappen, zonder kookmodus")
                }
                action("Opruimen", systemImage: "archivebox", action: onArchive,
                       hint: "Verdwijnt uit lijsten en voorstellen; terug te halen bij Opgeruimd")
            }
            .disabled(busy)
            .opacity(busy ? 0.5 : 1)
        }
    }

    private func action(_ title: String, systemImage: String, action: @escaping () -> Void,
                        hint: String) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Color.misoBlue)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Color.misoCream, in: Capsule())
                .overlay { Capsule().strokeBorder(Color.misoBlue.opacity(0.3), lineWidth: 1) }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title): \(recipe.name)")
        .accessibilityHint(hint)
    }
}

/// Recept openen vanaf de opruimlijst (alleen het id is bekend).
struct RecipeSummaryLink: Hashable {
    let id: Int
}
