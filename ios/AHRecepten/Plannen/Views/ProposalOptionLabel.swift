import SwiftUI

/// Foto, naam (met ♥ voor favorieten) en tijd/"Allerhande" van een voorgesteld recept.
struct ProposalOptionLabel: View {
    let option: ProposalOption
    var imageSize: CGFloat = 80
    var prominent = true

    var body: some View {
        HStack(spacing: 12) {
            RecipeImage(path: option.imageUrl, size: imageSize)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if option.favorite {
                        Text("♥").foregroundStyle(Color.misoOrange).accessibilityHidden(true)
                    }
                    Text(option.name)
                        .multilineTextAlignment(.leading)
                }
                .font(.system(prominent ? .headline : .subheadline, design: .rounded).weight(prominent ? .bold : .semibold))
                .foregroundStyle(Color.misoBlue)
                HStack(spacing: 6) {
                    if !option.totalTime.isEmpty {
                        Label(option.totalTime, systemImage: "clock")
                            .font(.misoCaption)
                            .foregroundStyle(.secondary)
                    }
                    if option.allerhande {
                        Text("Allerhande").misoChip(.misoLilac)
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
        if option.favorite { parts.append("favoriet") }
        if !option.totalTime.isEmpty { parts.append(option.totalTime) }
        if option.allerhande { parts.append("uit Allerhande") }
        return parts.joined(separator: ", ")
    }
}
