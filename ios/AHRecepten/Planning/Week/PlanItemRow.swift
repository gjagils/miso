import SwiftUI

/// Eén planregel op een dagkaart: recept (met foto), restje of "hebben we al", met personen, extra's en
/// gezondheidschips.
struct PlanItemRow: View {
    let item: PlanItem
    let persons: Int
    var profile: HealthProfile?
    /// Opent het recept (alleen bij een recept).
    var onOpenRecipe: (() -> Void)?
    /// Personen aanpassen (alleen als de regel een `entry_id` heeft).
    var onPersons: ((Int) -> Void)?
    /// Staan de boodschappen al op het AH-lijstje of in de bestelling?
    var listBadge: ListStatusEntry?

    private var meta: String {
        var parts: [String] = []
        switch item.kind {
        case .recipe, .other:
            if onPersons == nil && persons > 0 { parts.append("voor \(persons)") }
            if let cookDouble = item.cookDouble { parts.append(cookDouble.summary) }
        case .leftover:
            if onPersons == nil && persons > 0 { parts.append("voor \(persons)") }
            parts.append("geen boodschappen")
        case .stock:
            parts.append("hebben we al")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            PlanItemThumbnail(item: item)
            VStack(alignment: .leading, spacing: 4) {
                if let onOpenRecipe {
                    Button(action: onOpenRecipe) {
                        Text(RecipeDisplayName.short(item.title))
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .foregroundStyle(Color.misoBlue)
                            .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityHint("Opent het recept")
                } else {
                    Text(item.title)
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundStyle(Color.misoBlue)
                }
                if !meta.isEmpty {
                    Text(meta).font(.misoCaption).foregroundStyle(.secondary)
                }
                if let listBadge { ListStatusBadge(entry: listBadge) }
                if !item.extras.isEmpty {
                    PlanExtrasList(extras: item.extras)
                }
                if let chips = profile?.chips, !chips.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(chips, id: \.self) { Text($0).misoChip(.misoMint) }
                    }
                    .accessibilityElement(children: .combine)
                }
                if let onPersons, item.hasPersons {
                    HStack(spacing: 8) {
                        Text("voor").font(.misoCaption).foregroundStyle(.secondary)
                        PersonsStepper(value: persons, label: "Personen voor \(item.title)", onChange: onPersons)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}
