import SwiftUI

/// De Miso-kat in een bepaalde pose. Decoratief, dus verborgen voor VoiceOver.
struct MascotView: View {
    let pose: String
    var size: CGFloat = 120

    var body: some View {
        Image("Miso/\(pose)")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Lege staat / foutstaat met mascotte, titel en uitleg.
struct EmptyStateView: View {
    let pose: String
    let title: String
    var message: String?
    var size: CGFloat = 140

    var body: some View {
        VStack(spacing: 8) {
            MascotView(pose: pose, size: size)
            Text(title).font(.misoTitle2).foregroundStyle(Color.misoBlue).multilineTextAlignment(.center)
            if let message {
                Text(message).font(.misoBody).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

/// Foutmelding met verbaasde Miso.
struct ErrorStateView: View {
    let message: String
    var body: some View {
        EmptyStateView(pose: "surprised", title: "Oeps, dat ging mis", message: message, size: 110)
    }
}

/// Wordmark "Miso" met oranje accent.
struct MisoWordmark: View {
    /// Groeit mee met de tekstgrootte van het systeem.
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 48

    init(size: CGFloat = 48) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: .largeTitle)
    }

    var body: some View {
        HStack(spacing: 0) {
            Text("Mis").foregroundStyle(Color.misoBlue)
            Text("o").foregroundStyle(Color.misoOrange)
        }
        .font(.system(size: size, weight: .heavy, design: .rounded))
        .accessibilityLabel("Miso")
    }
}

struct RecipeImage: View {
    @Environment(Session.self) private var session
    let path: String
    var size: CGFloat = 56

    private var placeholder: some View {
        ZStack {
            Color.misoLilac.opacity(0.5)
            Image("Miso/hungry").resizable().scaledToFit().padding(size * 0.12)
        }
    }

    var body: some View {
        Group {
            if let url = session.api?.imageURL(path) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size > 100 ? 20 : 12))
        .accessibilityHidden(true)
    }
}

struct GlutenFreeChip: View {
    var body: some View {
        Text("glutenvrij").misoChip(.misoMint)
    }
}

struct RecipeRow: View {
    let recipe: RecipeSummary

    var body: some View {
        HStack(spacing: 12) {
            RecipeImage(path: recipe.imageUrl, size: 64)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if recipe.isFavorite {
                        Text("♥").foregroundStyle(Color.misoOrange).accessibilityLabel("Favoriet")
                    }
                    Text(recipe.displayName)
                    if !recipe.fansText.isEmpty {
                        // Wie het een favoriet vindt ("H S").
                        Text(recipe.fansText)
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(Color.misoOrange)
                            .accessibilityLabel("favoriet van \(recipe.fansText)")
                    }
                }
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(Color.misoBlue)
                let meta = [recipe.servings, recipe.totalTime].filter { !$0.isEmpty }.joined(separator: " · ")
                if !meta.isEmpty {
                    Text(meta).font(.misoCaption).foregroundStyle(.secondary)
                }
                if recipe.gfMode.isActive || recipe.showsMealKitTag || recipe.isByHeart {
                    HStack(spacing: 4) {
                        if recipe.showsMealKitTag { Text("Maaltijdpakket").misoChip(.misoOrange) }
                        if recipe.isByHeart { Text("uit mijn hoofd").misoChip(.misoLilac) }
                        if recipe.gfMode.isActive { GlutenFreeChip() }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
        .contentShape(.rect)
    }
}
