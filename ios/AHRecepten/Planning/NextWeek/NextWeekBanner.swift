import SwiftUI

/// "Volgende week: 3 van 5 doordeweekse dagen gepland · nog 2 dagen tot zondag (besteldag)".
/// Groot vanaf 2 dagen voor de besteldag; anders één compacte regel. De knop opent Plannen voor die week.
struct NextWeekBanner: View {
    let model: NextWeekModel
    let onPlan: () -> Void

    var body: some View {
        if let status = model.status {
            if model.isProminent {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        MascotView(pose: "checklist", size: 72)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Tijd om volgende week te plannen")
                                .font(.misoHeadline).foregroundStyle(Color.misoBlue)
                                .accessibilityAddTraits(.isHeader)
                            Text(status.message).font(.callout).foregroundStyle(Color.misoBlue)
                            PlannedDots(planned: status.progressPlanned, total: status.progressTotal)
                        }
                    }
                    Button("Plan volgende week", action: onPlan)
                        .buttonStyle(.misoPrimary)
                }
                .misoCard()
                .overlay {
                    RoundedRectangle(cornerRadius: 20).strokeBorder(Color.misoOrange, lineWidth: 2)
                }
            } else {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        PlannedDots(planned: status.progressPlanned, total: status.progressTotal)
                        Text(status.message).font(.footnote).foregroundStyle(Color.misoBlue)
                    }
                    Spacer(minLength: 0)
                    if !status.isComplete {
                        Button("Plan", action: onPlan)
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                            .foregroundStyle(Color.misoBlue)
                            .frame(minWidth: 44, minHeight: 44)
                            .accessibilityLabel("Plan volgende week")
                    }
                }
                .misoCard(padding: 12)
            }
        }
    }
}
