import SwiftUI

/// Het gerecht van vandaag, groot, met "Start met koken".
struct TodayHeroCard: View {
    let item: PlanItem
    /// Volledig recept (nil zolang het laadt, of bij restjes/voorraad).
    let recipe: RecipeDetail?
    /// Recept wordt opgehaald na een tik op "Start met koken".
    var starting = false
    /// Eerlijke tijd en "zet eerst de oven aan" (uit de bereiding).
    var hints: CookHints?
    var moving = false
    /// Kind: altijd de kookmodus (ook bij "uit mijn hoofd": dat weet papa of mama, niet per se jij).
    var alwaysCook = false
    let onCook: () -> Void
    /// "Iets snellers": Plannen voor vandaag met de wens "snel" (vervangt pas bij bevestigen). nil = kind.
    var onQuicker: (() -> Void)?
    /// "Verplaats naar morgen". nil = kind of niet aan te passen.
    var onMove: (() -> Void)?

    private var isRecipe: Bool { item.kind == .recipe && item.recipeId != nil }
    private var byHeart: Bool { !alwaysCook && (recipe?.isByHeart ?? false) }

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
                    Text(RecipeDisplayName.short(item.title))
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
            if isRecipe, let ready = hints?.readyText(startingAt: .now) {
                Label(ready, systemImage: "clock")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color.misoBlue)
            }
            if isRecipe, let oven = hints?.ovenText {
                Label(oven, systemImage: "flame")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color.misoInk)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.misoOrange.opacity(0.35), in: Capsule())
            }
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
            if onQuicker != nil || onMove != nil {
                HStack(spacing: 8) {
                    if let onQuicker {
                        Button("Iets snellers", systemImage: "hare", action: onQuicker)
                            .accessibilityHint("Miso stelt snelle recepten voor vandaag voor; dit gerecht blijft tot je kiest")
                    }
                    if let onMove {
                        Button(action: onMove) {
                            if moving { ProgressView() } else { Label("Naar morgen", systemImage: "arrow.turn.down.right") }
                        }
                        .disabled(moving)
                        .accessibilityLabel("Verplaats naar morgen")
                    }
                }
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Color.misoBlue)
                .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .misoCard()
        .overlay {
            RoundedRectangle(cornerRadius: 20).strokeBorder(Color.misoOrange, lineWidth: 2)
        }
    }

    private var meta: String {
        switch item.kind {
        case .recipe, .other:
            let time = hints?.timeText ?? item.recipe?.totalTime ?? ""
            return [item.persons > 0 ? "voor \(item.persons)" : "", time]
                .filter { !$0.isEmpty }.joined(separator: " · ")
        case .leftover:
            return "Restjes, niets te koken"
        case .stock:
            return item.extras.isEmpty ? "Hebben we al" : "Hebben we al, plus \(item.extras.map(\.text).joined(separator: ", "))"
        }
    }
}
