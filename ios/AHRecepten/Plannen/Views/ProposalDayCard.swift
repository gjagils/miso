import SwiftUI

/// Voorstel voor één dag: Miso's keuze groot, tot twee alternatieven om op te tikken.
struct ProposalDayCard: View {
    let day: ProposalDay
    let chosen: ProposalOption?
    let alternatives: [(index: Int, option: ProposalOption)]
    /// recept-id → initialen van wie het een favoriet vindt.
    var fans: [Int: [String]] = [:]
    /// "Wijzig": dit vervangt wat er stond.
    var replacing = false
    let onChoose: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(KiezenDates.label(day.date))
                    .font(.misoHeadline)
                    .foregroundStyle(Color.misoBlue)
                if !day.label.isEmpty {
                    Text("· \(day.label)").font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            if replacing {
                Text("Vervangt wat er stond").misoChip(.misoLilac)
            }

            switch day.kind {
            case .vriezer:
                Label("Iets uit de vriezer (geen boodschappen)", systemImage: "snowflake")
                    .foregroundStyle(Color.misoBlue)
            case .overslaan:
                Text("Niets gepland").foregroundStyle(.secondary)
            case .taken:
                Label("Staat al: \(day.taken ?? "")", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            case .none:
                Text("Geen recept gevonden. Kies bij Andere wensen iets anders voor deze dag.")
                    .foregroundStyle(.secondary)
            case .recipe:
                if let chosen {
                    // Eigen recept: tik om het te bekijken (terug brengt je naar het voorstel).
                    if let id = chosen.recipeId {
                        NavigationLink(value: RecipeSummaryLink(id: id)) {
                            HStack(spacing: 8) {
                                ProposalOptionLabel(option: chosen, imageSize: 88, fans: fansOf(chosen))
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Bekijk het recept")
                    } else {
                        ProposalOptionLabel(option: chosen, imageSize: 88, fans: fansOf(chosen))
                    }
                }
                if !alternatives.isEmpty {
                    Text("Of wissel naar")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(alternatives, id: \.index) { alt in
                        Button {
                            onChoose(alt.index)
                        } label: {
                            HStack(spacing: 8) {
                                ProposalOptionLabel(option: alt.option, imageSize: 48, prominent: false, fans: fansOf(alt.option))
                                Image(systemName: "arrow.left.arrow.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Color.misoOrange)
                                    .accessibilityHidden(true)
                            }
                            .padding(8)
                            .background(Color.misoCream, in: .rect(cornerRadius: 14))
                            .contentShape(.rect(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Wissel naar \(alt.option.name)")
                        .accessibilityAddTraits(.isButton)
                    }
                }
            }
        }
        .misoCard()
    }

    private func fansOf(_ option: ProposalOption) -> [String] {
        option.recipeId.flatMap { fans[$0] } ?? []
    }
}
