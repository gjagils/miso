import SwiftUI

/// "Gezin en besteldag": gezinsgrootte en besteldag.
struct HouseholdSettingsSection: View {
    let settings: PlanSettings?
    let errorText: String?
    let onHouseholdSize: (Int) -> Void
    let onOrderWeekday: (Int) -> Void

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
            } else if let errorText {
                Text(errorText).font(.callout).foregroundStyle(.secondary)
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        } header: {
            Text("Gezin en besteldag").misoSectionHeader()
        } footer: {
            Text("Nieuwe planregels zijn standaard voor de gezinsgrootte. Op de besteldag doe je de boodschappen voor de week erna; vanaf 2 dagen ervoor laat Miso zien wat er nog gepland moet worden.")
        }
        .misoRow()
    }
}
