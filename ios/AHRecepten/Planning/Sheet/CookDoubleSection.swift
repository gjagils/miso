import SwiftUI

/// "Kook dubbel" met de keuze "morgen opeten" / "naar de vriezer".
struct CookDoubleSection: View {
    @Binding var isOn: Bool
    @Binding var choice: CookDouble

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Kook dubbel", isOn: $isOn.animation())
                .font(.misoHeadline)
                .foregroundStyle(Color.misoBlue)
                .tint(Color.misoOrange)
            if isOn {
                Picker("Wat doe je met de rest?", selection: $choice) {
                    ForEach(CookDouble.allCases) { option in
                        Text(option.choiceLabel).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                Text(choice == .tomorrow
                     ? "Miso zet de rest morgen in het weekmenu en koopt dubbel in."
                     : "Miso koopt dubbel in en zet de helft in de vriezer.")
                    .font(.misoCaption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
