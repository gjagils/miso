import SwiftUI

/// Niets gepland vandaag: drie snelle voorstellen en een knop naar Plannen.
struct TodaySuggestionsCard: View {
    let suggestions: [TodaySuggestion]
    let planningID: String?
    let onPick: (TodaySuggestion) -> Void
    /// nil = geen knop naar Plannen (kind).
    var onPlan: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                MascotView(pose: "hungry", size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nog niets voor vandaag")
                        .font(.misoHeadline)
                        .foregroundStyle(Color.misoBlue)
                        .accessibilityAddTraits(.isHeader)
                    Text("Tik op een voorstel en het staat op het menu.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(suggestions) { suggestion in
                Button {
                    onPick(suggestion)
                } label: {
                    HStack(spacing: 12) {
                        switch suggestion.kind {
                        case .recipe(let recipe):
                            RecipeImage(path: recipe.imageUrl, size: 56)
                        case .freezer:
                            MascotView(pose: "box", size: 48)
                                .frame(width: 56, height: 56)
                                .background(Color.misoLilac.opacity(0.5), in: .rect(cornerRadius: 12))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.title)
                                .font(.system(.body, design: .rounded).weight(.semibold))
                                .foregroundStyle(Color.misoBlue)
                                .multilineTextAlignment(.leading)
                            Text(suggestion.subtitle).font(.misoCaption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        if planningID == suggestion.id {
                            ProgressView()
                        } else {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundStyle(Color.misoOrange)
                                .accessibilityHidden(true)
                        }
                    }
                    .padding(8)
                    .background(Color.misoCream, in: .rect(cornerRadius: 14))
                    .contentShape(.rect(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(planningID != nil)
                .accessibilityElement(children: .combine)
                .accessibilityHint("Zet dit vandaag op het menu")
            }
            if let onPlan {
                Button("Toch iets anders? Naar Plannen", systemImage: "calendar.badge.plus", action: onPlan)
                    .buttonStyle(.misoSecondary)
            }
        }
        .misoCard()
    }
}
