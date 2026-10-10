import SwiftUI

/// Kop van een dag in het weekmenu, met "+" om iets te plannen.
struct PlanDayHeader: View {
    let day: PlanDay
    /// nil = geen "+" (kind).
    var onAdd: (() -> Void)?

    var body: some View {
        HStack {
            Text(day.label).misoSectionHeader()
            if day.today { Text("vandaag").misoChip(.misoOrange) }
            Spacer()
            if let onAdd {
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.body.weight(.bold))
                    .foregroundStyle(Color.misoInk)
                    .frame(width: 32, height: 32)
                    .background(Color.misoOrange, in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Iets plannen op \(day.label)")
            }
        }
    }
}
