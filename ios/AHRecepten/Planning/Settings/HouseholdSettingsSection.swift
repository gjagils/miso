import SwiftUI

/// "Gezin en besteldag": gezinsgrootte en besteldag.
struct HouseholdSettingsSection: View {
    let settings: PlanSettings?
    let errorText: String?
    let onHouseholdSize: (Int) -> Void
    let onOrderWeekday: (Int) -> Void
    var onWeekBudget: ((Int) -> Void)?

    var body: some View {
        Section {
            if let settings {
                HStack {
                    Text("Gezinsgrootte").foregroundStyle(Color.misoBlue)
                    Spacer()
                    PersonsStepper(value: settings.householdSize, label: "Gezinsgrootte", onChange: onHouseholdSize)
                }
                .frame(minHeight: 44)
                Menu {
                    ForEach(PlanSettings.weekdayNames.indices, id: \.self) { index in
                        Button {
                            onOrderWeekday(index)
                        } label: {
                            if index == settings.orderWeekday {
                                Label(PlanSettings.weekdayNames[index].capitalized, systemImage: "checkmark")
                            } else {
                                Text(PlanSettings.weekdayNames[index].capitalized)
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text("Besteldag").foregroundStyle(Color.misoBlue)
                        Spacer()
                        Text(settings.orderWeekdayName.capitalized).foregroundStyle(.secondary)
                        Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                    .contentShape(.rect)
                }
                .accessibilityLabel("Besteldag")
                .accessibilityValue(settings.orderWeekdayName)
                if let onWeekBudget {
                    Stepper(value: Binding(get: { settings.weekBudget }, set: { onWeekBudget($0) }), in: 0...9999, step: 10) {
                        HStack {
                            Text("Weekbudget").foregroundStyle(Color.misoBlue)
                            Spacer()
                            Text(settings.weekBudget == 0 ? "geen" : Euro.format(Double(settings.weekBudget)))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(minHeight: 44)
                    .accessibilityValue(settings.weekBudget == 0 ? "geen budget" : "\(settings.weekBudget) euro per week")
                }
            } else if let errorText {
                Text(errorText).font(.callout).foregroundStyle(.secondary)
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        } header: {
            Text("Gezin en besteldag").misoSectionHeader()
        } footer: {
            Text("Nieuwe planregels zijn standaard voor de gezinsgrootte. Het weekbudget vergelijkt Miso met de geschatte kosten van de week. Op de besteldag doe je de boodschappen voor de week erna; vanaf 2 dagen ervoor laat Miso zien wat er nog gepland moet worden.")
        }
        .misoRow()
    }
}
