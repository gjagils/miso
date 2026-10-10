import SwiftUI

/// Eén dag op het wensen-scherm: zes hoofdknoppen (+ "Meer…"), en een veld voor een gerecht.
/// Bezette dagen tonen wat er staat met Wijzig / Haal weg; voorbije dagen zijn alleen-lezen.
struct WishDayRow: View {
    let day: PlannenDay
    @Binding var wish: WishInput
    var focus: FocusState<String?>.Binding
    /// Bezette dag leegmaken en meteen een nieuwe wens kiezen.
    var onChange: (() -> Void)?
    /// Bezette dag leegmaken (de ouder vraagt eerst om bevestiging).
    var onRemove: (() -> Void)?
    var clearing = false
    @State private var showMore = false

    /// "Meer…" staat open als je erom vroeg, of als de gekozen knop daar zit (bijv. via de zin).
    private var moreVisible: Bool { showMore || (wish.chip?.isMore ?? false) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(day.label)
                    .font(.misoHeadline)
                    .foregroundStyle(Color.misoBlue)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if day.isOpen, let value = wish.value {
                    // Samenvatting voor wie snel scant.
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
                if day.canClear, onChange != nil || onRemove != nil {
                    HStack(spacing: 8) {
                        if let onChange {
                            smallButton("Wijzig", systemImage: "arrow.triangle.2.circlepath", action: onChange,
                                        hint: "Haalt \(day.taken) weg zodat je een nieuwe wens kiest")
                        }
                        if let onRemove {
                            smallButton("Haal weg", systemImage: "trash", action: onRemove,
                                        hint: "Maakt \(day.label) leeg")
                        }
                        if clearing { ProgressView() }
                    }
                    .disabled(clearing)
                }
            } else if day.isPast {
                Text("Voorbij").font(.callout).foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(WishChip.main) { chip($0) }
                    if moreVisible {
                        ForEach(WishChip.more) { chip($0) }
                    }
                    Button(moreVisible ? "Minder" : "Meer…") {
                        withAnimation(.snappy) { showMore = !moreVisible }
                    }
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color.misoBlue)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .contentShape(.rect)
                    .buttonStyle(.plain)
                    .disabled(wish.chip?.isMore ?? false)
                    .accessibilityLabel(moreVisible ? "Minder knoppen" : "Meer knoppen: noedels, vis, vega, kip, snel klaar, overslaan")
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
    }

    private func chip(_ chip: WishChip) -> some View {
        WishChipButton(chip: chip, selected: wish.chip == chip) {
            wish.toggle(chip)
        }
    }

    private func smallButton(_ title: String, systemImage: String, action: @escaping () -> Void,
                             hint: String) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Color.misoBlue)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Color.misoCream, in: Capsule())
                .overlay { Capsule().strokeBorder(Color.misoBlue.opacity(0.3), lineWidth: 1) }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityHint(hint)
    }
}
