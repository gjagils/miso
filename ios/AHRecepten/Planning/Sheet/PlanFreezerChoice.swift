import SwiftUI

/// Vriezer-item om te kiezen bij "Uit de vriezer".
struct PlanFreezerChoice: View {
    let item: FreezerItem
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.misoOrange : Color.secondary)
                    .accessibilityHidden(true)
                Text(item.name).foregroundStyle(Color.misoBlue)
                Spacer()
                Text(plural(item.portions, "portie", "porties")).font(.caption).foregroundStyle(.secondary)
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
