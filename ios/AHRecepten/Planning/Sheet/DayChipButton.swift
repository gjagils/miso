import SwiftUI

/// Eén dagchip: "ma 12" met een stip als er al iets staat.
struct DayChipButton: View {
    let chip: DayChip
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(chip.weekdayShort)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                Text(chip.dayNumber, format: .number)
                    .font(.system(.headline, design: .rounded).weight(.heavy))
                Circle()
                    .fill(chip.isOccupied ? (selected ? Color.misoInk : Color.misoOrange) : .clear)
                    .frame(width: 6, height: 6)
            }
            .foregroundStyle(selected ? Color.misoInk : Color.misoBlue)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(selected ? Color.misoOrange : Color.misoCard, in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(chip.isToday && !selected ? Color.misoOrange : Color.misoBlue.opacity(0.12),
                                  lineWidth: chip.isToday && !selected ? 2 : 1)
            }
            .opacity(chip.isPast ? 0.4 : 1)
            .contentShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(chip.isPast)
        .accessibilityLabel(chip.accessibilityLabel)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
