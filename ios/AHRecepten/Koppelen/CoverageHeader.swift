import SwiftUI

/// "94,3% gekoppeld" met voortgangsbalk en het aantal complete recepten.
struct CoverageHeader: View {
    let totals: CoverageTotals
    let openLines: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                MascotView(pose: totals.fraction >= 1 ? "celebrate" : "checklist", size: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(totals.pctText) gekoppeld")
                        .font(.misoTitle2).foregroundStyle(Color.misoBlue)
                        .contentTransition(.numericText())
                    Text(totals.completeText).font(.misoCaption).foregroundStyle(.secondary)
                    if openLines > 0 {
                        Text("Nog \(plural(openLines, "ingrediëntregel", "ingrediëntregels")) zonder AH-product")
                            .font(.misoCaption).foregroundStyle(.secondary)
                    }
                }
            }
            ProgressView(value: totals.fraction)
                .tint(Color.misoOrange)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
        .animation(.default, value: totals)
        .accessibilityElement(children: .combine)
    }
}
