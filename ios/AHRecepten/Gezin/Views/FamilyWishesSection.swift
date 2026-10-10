import SwiftUI

/// "Wensen van het gezin" bovenaan Plannen (ouders): boodschappen eerst ("Op AH-lijstje"), daarna eten met
/// een dag en "Zet op deze dag". ✕ handelt een wens af.
struct FamilyWishesSection: View {
    let wishes: [FamilyWish]
    /// Open dagen (ook weekend) waarop een wens gezet kan worden.
    let days: [PlannenDay]
    let busyID: Int?
    let message: String?
    let onPlace: (FamilyWish, String) -> Void
    let onToList: (FamilyWish) -> Void
    let onDone: (FamilyWish) -> Void
    let onDismissMessage: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Wensen van het gezin", systemImage: "heart.text.square")
                .font(.misoHeadline)
                .foregroundStyle(Color.misoBlue)
                .accessibilityAddTraits(.isHeader)
            if let message {
                HStack(alignment: .top) {
                    Text(message).font(.callout).foregroundStyle(Color.misoInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Sluit", systemImage: "xmark", action: onDismissMessage)
                        .labelStyle(.iconOnly)
                        .frame(minWidth: 44, minHeight: 44)
                        .buttonStyle(.borderless)
                }
                .padding(.leading, 10)
                .background(Color.misoMint, in: .rect(cornerRadius: 12))
            }
            ForEach(wishes) { wish in
                FamilyWishRow(wish: wish, days: days, busy: busyID == wish.id,
                              onPlace: { onPlace(wish, $0) }, onToList: { onToList(wish) }, onDone: { onDone(wish) })
            }
        }
        .misoCard()
    }
}

/// Eén wens met dagkeuze (eten) of "Op AH-lijstje" (boodschap).
struct FamilyWishRow: View {
    let wish: FamilyWish
    let days: [PlannenDay]
    let busy: Bool
    let onPlace: (String) -> Void
    let onToList: () -> Void
    let onDone: () -> Void
    @State private var date = ""

    private var chosenDate: String? {
        days.contains { $0.date == date } ? date : days.first?.date
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(wish.sentence)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color.misoBlue)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Wens wegklikken", systemImage: "xmark", action: onDone)
                    .labelStyle(.iconOnly)
                    .foregroundStyle(Color.misoBlue)
                    .frame(minWidth: 44, minHeight: 44)
                    .buttonStyle(.borderless)
                    .disabled(busy)
            }
            HStack(spacing: 8) {
                if wish.isGrocery {
                    Button(action: onToList) {
                        if busy { ProgressView() } else { Label("Op AH-lijstje", systemImage: "cart.badge.plus") }
                    }
                    .buttonStyle(.misoPrimary)
                } else if days.isEmpty {
                    Text("Geen open dag meer deze week.").font(.callout).foregroundStyle(.secondary)
                } else {
                    Picker("Op welke dag?", selection: $date) {
                        ForEach(days) { Text($0.label).tag($0.date) }
                    }
                    .pickerStyle(.menu)
                    .onAppear { if let chosenDate { date = chosenDate } }
                    .onChange(of: days) { if let chosenDate { date = chosenDate } }
                    .tint(Color.misoBlue)
                    .frame(minHeight: 44)
                    Button {
                        if let chosenDate { onPlace(chosenDate) }
                    } label: {
                        if busy { ProgressView() } else { Text("Zet op deze dag") }
                    }
                    .buttonStyle(.misoPrimary)
                }
            }
            .disabled(busy)
        }
        .padding(10)
        .background(Color.misoCream, in: .rect(cornerRadius: 14))
    }
}
