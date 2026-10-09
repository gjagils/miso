import SwiftUI

struct SettingsView: View {
    @Environment(Session.self) private var session
    @State private var planSettings = PlanSettingsModel()
    @AppStorage(Appearance.storageKey) private var appearance = Appearance.system

    private var settingsURL: URL? {
        guard let base = URL(string: session.serverURL.trimmingCharacters(in: .whitespaces)), base.scheme != nil else { return nil }
        return base.appending(path: "settings")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    EmptyStateView(pose: "tech", title: "Miso", message: "Altijd iets lekkers op de planning.", size: 110)
                        .listRowBackground(Color.clear)
                }
                HouseholdSettingsSection(settings: planSettings.settings, errorText: planSettings.errorText,
                                         onHouseholdSize: setHouseholdSize, onOrderWeekday: setOrderWeekday)
                ReminderSettingsSection()
                Section {
                    Picker("Weergave", selection: $appearance) {
                        ForEach(Appearance.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(minHeight: 44)
                } header: { Text("Weergave").misoSectionHeader() }
                .misoRow()
                Section {
                    NavigationLink {
                        FreezerView()
                    } label: {
                        Label("Vriezer", systemImage: "snowflake")
                            .font(.misoButton)
                            .foregroundStyle(Color.misoBlue)
                            .frame(minHeight: 44)
                    }
                    NavigationLink {
                        MissingView()
                    } label: {
                        Label("Ontbrekend", systemImage: "cart.badge.questionmark")
                            .font(.misoButton)
                            .foregroundStyle(Color.misoBlue)
                            .frame(minHeight: 44)
                    }
                    .accessibilityHint("Ingrediënten zonder AH-product koppelen of op niet nodig zetten")
                }
                .misoRow()
                Section {
                    Text(session.serverURL).font(.misoBody)
                    Button("Uitloggen", role: .destructive, action: logout)
                        .frame(minHeight: 44)
                } header: { Text("Server").misoSectionHeader() }
                .misoRow()
                Section {
                    Text("De AH-koppeling stel je eenmalig in op de website van de server, onder Instellingen. Daar plak je de inlogcode van ah.nl.")
                        .font(.callout)
                    if let url = settingsURL {
                        Link("Instellingen op de server openen", destination: url)
                            .font(.misoButton).foregroundStyle(Color.misoBlue)
                            .frame(minHeight: 44)
                    }
                } header: { Text("Albert Heijn").misoSectionHeader() }
                .misoRow()
            }
            .misoScreen()
            .navigationTitle("Meer")
            .task { await loadSettings() }
            .refreshable { await loadSettings() }
        }
    }

    private func loadSettings() async {
        guard let api = session.api else { return }
        await planSettings.load(api: api)
    }

    private func setHouseholdSize(_ value: Int) {
        guard let api = session.api else { return }
        planSettings.setHouseholdSize(value, api: api)
    }

    private func setOrderWeekday(_ weekday: Int) {
        guard let api = session.api else { return }
        Task { await planSettings.setOrderWeekday(weekday, api: api) }
    }

    private func logout() {
        session.logout()
    }
}
