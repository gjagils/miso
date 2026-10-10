import SwiftUI

/// Eén wens-knop ("Rijst", "Geen idee"). Aan = oranje met vinkje (niet alleen kleur).
struct WishChipButton: View {
    let chip: WishChip
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if selected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.heavy))
                        .accessibilityHidden(true)
                }
                Text(chip.label)
            }
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .foregroundStyle(selected ? Color.misoInk : Color.misoBlue)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(selected ? Color.misoOrange : Color.misoCream, in: Capsule())
            .overlay {
                Capsule().strokeBorder(selected ? Color.clear : Color.misoBlue.opacity(0.25), lineWidth: 1)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
