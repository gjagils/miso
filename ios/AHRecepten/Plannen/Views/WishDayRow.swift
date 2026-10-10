import SwiftUI

/// Eén dag op het wensen-scherm: knoppen plus een veld voor een gerecht. Bezette of voorbije dagen alleen-lezen.
struct WishDayRow: View {
    let day: PlannenDay
    @Binding var wish: WishInput
    var focus: FocusState<String?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(day.label)
                    .font(.misoHeadline)
                    .foregroundStyle(Color.misoBlue)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if day.isOpen, let value = wish.value {
                    // Samenvatting voor wie snel scant (en voor VoiceOver bij de kop).
                    Text(wish.chip?.label ?? value)
                        .lineLimit(1)
                        .misoChip(.misoMint)
                        .accessibilityLabel("Wens: \(wish.chip?.label ?? value)")
                }
            }
            if !day.taken.isEmpty {
                Label("Staat al: \(day.taken)", systemImage: "checkmark.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if day.isPast {
                Text("Voorbij").font(.callout).foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(WishChip.allCases) { chip in
                        WishChipButton(chip: chip, selected: wish.chip == chip) {
                            wish.toggle(chip)
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Wens voor \(day.label)")
                TextField("of typ een gerecht, bijv. lasagne", text: $wish.text)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.done)
                    .focused(focus, equals: day.date)
                    .misoField()
                    .accessibilityLabel("Gerecht voor \(day.label)")
                    .onChange(of: wish.text) { _, text in
                        if !text.isEmpty && wish.chip != nil { wish.chip = nil }
                    }
            }
        }
        .misoCard()
        .opacity(day.isOpen ? 1 : 0.75)
    }
}
