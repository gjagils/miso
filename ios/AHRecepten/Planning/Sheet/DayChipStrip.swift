import SwiftUI

/// "Welke dag?": 7 dagchips met vorige/volgende week en een regel met wat er die dag al staat.
struct DayChipStrip: View {
    let chips: [DayChip]
    let selected: String?
    let info: String
    let onSelect: (DayChip) -> Void
    let onShift: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Welke dag?").font(.misoHeadline).foregroundStyle(Color.misoBlue)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 4) {
                Button("Vorige 7 dagen", systemImage: "chevron.left", action: showPrevious)
                    .labelStyle(.iconOnly)
                    .frame(width: 30, height: 44)
                    .contentShape(.rect)
                HStack(spacing: 4) {
                    ForEach(chips) { chip in
                        DayChipButton(chip: chip, selected: chip.date == selected) { onSelect(chip) }
                    }
                }
                Button("Volgende 7 dagen", systemImage: "chevron.right", action: showNext)
                    .labelStyle(.iconOnly)
                    .frame(width: 30, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.misoBlue)
            Text(info)
                .font(.misoCaption)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.updatesFrequently)
        }
    }

    private func showPrevious() { onShift(-7) }
    private func showNext() { onShift(7) }
}
