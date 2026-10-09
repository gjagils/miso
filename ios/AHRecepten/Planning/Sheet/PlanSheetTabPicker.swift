import SwiftUI

/// Twee tabbladen die ook met lange tekst passen (een segmented control kapt "Uit de vriezer / hebben we al" af).
struct PlanSheetTabPicker: View {
    @Binding var selection: PlanSheetTab

    var body: some View {
        HStack(spacing: 6) {
            ForEach(PlanSheetTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    Text(tab.title)
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(selection == tab ? Color.misoInk : Color.misoBlue)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(.horizontal, 6)
                        .background(selection == tab ? Color.misoOrange : Color.clear, in: .rect(cornerRadius: 12))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == tab ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(4)
        .background(Color.misoCard, in: .rect(cornerRadius: 16))
    }
}
