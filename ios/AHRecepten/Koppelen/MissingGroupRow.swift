import SwiftUI

/// Eén zoekterm in Ontbrekend: de term, in hoeveel regels hij voorkomt en in welke recepten.
struct MissingGroupRow: View {
    let group: MissingGroup
    var busy = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(group.term)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color.misoBlue)
                Text(group.recipeNames.joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            if busy {
                ProgressView()
            } else if group.lines.count > 1 {
                Text("\(group.lines.count)×").misoChip(.misoOrange)
                    .accessibilityLabel("in \(group.lines.count) regels")
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
