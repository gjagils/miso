import SwiftUI

/// Compacte −/+ voor het aantal personen (1–20). VoiceOver: één regelbaar element.
struct PersonsStepper: View {
    let value: Int
    var range: ClosedRange<Int> = 1...20
    /// Naam voor VoiceOver, bijv. "Personen voor Lasagne".
    var label = "Personen"
    /// Eenheid voor VoiceOver ("persoon"/"personen", of "portie"/"porties").
    var unit: (one: String, many: String) = ("persoon", "personen")
    let onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button("Eén \(unit.one) minder", systemImage: "minus", action: decrement)
                .labelStyle(.iconOnly)
                .frame(width: 40, height: 40)
                .contentShape(.rect)
                .disabled(value <= range.lowerBound)
            Text(value, format: .number)
                .font(.system(.headline, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.misoBlue)
                .frame(minWidth: 24)
                .contentTransition(.numericText())
            Button("Eén \(unit.one) meer", systemImage: "plus", action: increment)
                .labelStyle(.iconOnly)
                .frame(width: 40, height: 40)
                .contentShape(.rect)
                .disabled(value >= range.upperBound)
        }
        .buttonStyle(.borderless)
        .font(.body.weight(.semibold))
        .foregroundStyle(Color.misoBlue)
        .background(Color.misoLilac.opacity(0.45), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(plural(value, unit.one, unit.many))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: increment()
            case .decrement: decrement()
            @unknown default: break
            }
        }
    }

    private func increment() {
        if value < range.upperBound { onChange(value + 1) }
    }

    private func decrement() {
        if value > range.lowerBound { onChange(value - 1) }
    }
}
