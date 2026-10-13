import SwiftUI

/// Foto, naam (met ♥ voor favorieten) en tijd/"Allerhande" van een voorgesteld recept.
struct ProposalOptionLabel: View {
    let option: ProposalOption
    var imageSize: CGFloat = 80
    var prominent = true
    /// Initialen van wie het een favoriet vindt ("H S").
    var fans: [String] = []

    var body: some View {
        HStack(spacing: 12) {
            RecipeImage(path: option.imageUrl, size: imageSize)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if option.favorite || !fans.isEmpty {
                        Text("♥").foregroundStyle(Color.misoOrange).accessibilityHidden(true)
                    }
                    Text(option.name)
                        .multilineTextAlignment(.leading)
                    if !fans.isEmpty {
                        Text(fans.joined(separator: " "))
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(Color.misoOrange)
                            .accessibilityHidden(true)
                    }
                }
                .font(.system(prominent ? .headline : .subheadline, design: .rounded).weight(prominent ? .bold : .semibold))
                .foregroundStyle(Color.misoBlue)
                FlowLayout(spacing: 6) {
                    if !option.totalTime.isEmpty {
                        Label(option.totalTime, systemImage: "clock")
                            .font(.misoCaption)
                            .foregroundStyle(.secondary)
                    }
                    if option.pack {
                        Text("Maaltijdpakket").misoChip(.misoOrange)
                    }
                    if option.allerhande {
                        Text("Allerhande").misoChip(.misoLilac)
                    }
                    if option.bonusSaving > 0 {
                        Text("bonus \(Euro.saving(option.bonusSaving))").misoChip(.misoOrange)
                    }
                    if option.kidsNight {
                        Text("kids-avond").misoChip(.misoMint)
                    }
                    ForEach(option.avoid, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(Color.misoInk)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.misoOrange.opacity(0.35), in: Capsule())
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = [option.name]
        if !fans.isEmpty { parts.append("favoriet van \(fans.joined(separator: ", "))") } else if option.favorite { parts.append("favoriet") }
        if option.pack { parts.append("maaltijdpakket") }
        if !option.totalTime.isEmpty { parts.append(option.totalTime) }
        if option.allerhande { parts.append("uit Allerhande") }
        if option.bonusSaving > 0 { parts.append("in de bonus, voordeel \(Euro.format(option.bonusSaving))") }
        if option.kidsNight { parts.append("makkelijk met kinderen, voor de kids-kookavond") }
        parts.append(contentsOf: option.avoid)
        return parts.joined(separator: ", ")
    }
}
