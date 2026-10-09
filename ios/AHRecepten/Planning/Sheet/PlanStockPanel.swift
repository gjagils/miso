import SwiftUI

/// Tabblad "Uit de vriezer / hebben we al": vriezer-items, vrije tekst en extra boodschappen.
struct PlanStockPanel: View {
    @Bindable var model: PlanSheetModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !model.freezer.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("In de vriezer").font(.misoHeadline).foregroundStyle(Color.misoBlue)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(model.freezer) { item in
                        PlanFreezerChoice(item: item, selected: model.selectedFreezer?.id == item.id) {
                            model.toggleFreezer(item)
                        }
                    }
                }
                .misoCard(padding: 12)
            }
            Text("Wat eten jullie?").font(.misoHeadline).foregroundStyle(Color.misoBlue)
            TextField("Bijv. pastasaus uit de vriezer, pannenkoeken", text: $model.stockText)
                .misoField()
                .onChange(of: model.stockText) { model.stockTextEdited() }
            Text("Moet er nog iets bij?").font(.misoHeadline).foregroundStyle(Color.misoBlue)
            TextField("Eén per regel, bijv. spaghetti", text: $model.extrasText, axis: .vertical)
                .lineLimit(3...)
                .misoField()
            Text("Miso zet de extra's op je AH-lijstje; de rest hebben jullie al.")
                .font(.misoCaption).foregroundStyle(.secondary)
        }
    }
}
