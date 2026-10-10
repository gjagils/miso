import SwiftUI

/// Het gerecht van vandaag, groot, met "Start met koken".
struct TodayHeroCard: View {
    let item: PlanItem
    /// Volledig recept (nil zolang het laadt, of bij restjes/voorraad).
    let recipe: RecipeDetail?
    /// Recept wordt opgehaald na een tik op "Start met koken".
    var starting = false
    let onCook: () -> Void
    /// "Toch iets anders": naar Plannen voor deze week (daar kun je vandaag wijzigen).
    let onSomethingElse: () -> Void

    private var isRecipe: Bool { item.kind == .recipe && item.recipeId != nil }
    private var byHeart: Bool { recipe?.isByHeart ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Vandaag eten we")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(.secondary)
            if isRecipe {
                RecipeImage(path: item.recipe?.imageUrl ?? "", size: 180)
                    .frame(maxWidth: .infinity)
            }
            HStack(alignment: .top, spacing: 12) {
                if !isRecipe {
                    PlanItemThumbnail(item: item, size: 72)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.misoTitle2)
                        .foregroundStyle(Color.misoBlue)
                        .fixedSize(horizontal: false, vertical: true)
                    if !meta.isEmpty {
                        Text(meta).font(.misoCaption).foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            if isRecipe, let summary = item.recipe {
                if byHeart {
                    Label("Je kent dit uit je hoofd", systemImage: "brain.head.profile")
                        .font(.callout)
                        .foregroundStyle(Color.misoBlue)
                    NavigationLink(value: summary) {
                        Text("Bekijk ingrediënten")
                    }
                    .buttonStyle(.misoPrimary)
                } else {
                    Button(action: onCook) {
                        if starting {
                            HStack(spacing: 8) { ProgressView(); Text("Start met koken") }
                        } else {
                            Label("Start met koken", systemImage: "flame")
                        }
                    }
                    .buttonStyle(.misoPrimary)
                    .disabled(starting)
                    NavigationLink(value: summary) {
                        Text("Bekijk recept")
                    }
                    .buttonStyle(.misoSecondary)
                    .accessibilityHint("Opent het recept met ingrediënten en bereiding")
                }
            }
            Button("Toch iets anders", systemImage: "arrow.triangle.2.circlepath", action: onSomethingElse)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Color.misoBlue)
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityHint("Opent Plannen, daar kun je vandaag wijzigen")
        }
        .misoCard()
        .overlay {
            RoundedRectangle(cornerRadius: 20).strokeBorder(Color.misoOrange, lineWidth: 2)
        }
    }

    private var meta: String {
        switch item.kind {
        case .recipe, .other:
            return [item.recipe?.totalTime ?? "", item.persons > 0 ? "voor \(item.persons)" : ""]
                .filter { !$0.isEmpty }.joined(separator: " · ")
        case .leftover:
            return "Restjes, niets te koken"
        case .stock:
            return item.extras.isEmpty ? "Hebben we al" : "Hebben we al, plus \(item.extras.map(\.text).joined(separator: ", "))"
        }
    }
}
