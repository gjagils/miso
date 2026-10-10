import SwiftUI

/// Filterknoppen Alle / ♥ Favorieten / Uit mijn hoofd / Maaltijdpakketten / Opgeruimd.
struct RecipeFilterBar: View {
    @Binding var selection: RecipeFilter

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(RecipeFilter.allCases) { filter in
                    let selected = filter == selection
                    Button {
                        selection = filter
                    } label: {
                        Text(filter.title)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(selected ? Color.misoInk : Color.misoBlue)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .background(selected ? Color.misoOrange : Color.misoCard, in: Capsule())
                            .overlay {
                                Capsule().strokeBorder(selected ? Color.clear : Color.misoBlue.opacity(0.2), lineWidth: 1)
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Filter recepten")
    }
}
