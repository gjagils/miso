import SwiftUI

struct SettingsView: View {
    @Environment(Session.self) private var session
    @Environment(FamilyModel.self) private var family
    @State private var showWho = false
    @State private var planSettings = PlanSettingsModel()
    @AppStorage(Appearance.storageKey) private var appearance = Appearance.system

    private var settingsURL: URL? {
        guard let base = URL(string: session.serverURL.trimmingCharacters(in: .whitespaces)), base.scheme != nil else { return nil }
        return base.appending(path: "settings")
    }

    /// Handleiding op de server (openbaar, zonder inloggen): /hulp
    private var helpURL: URL? {
        guard let base = URL(string: session.serverURL.trimmingCharacters(in: .whitespaces)), base.scheme != nil else { return nil }
        return base.appending(path: "hulp")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    EmptyStateView(pose: "tech", title: "Miso", message: "Altijd iets lekkers op de planning.", size: 110)
                        .listRowBackground(Color.clear)
                    if let helpURL {
                        Link(destination: helpURL) {
                            Label("Hoe werkt Miso?", systemImage: "book.closed")
                                .font(.misoButton).foregroundStyle(Color.misoBlue)
                                .frame(minHeight: 44)
                        }
                        .accessibilityHint("Opent de handleiding in Safari")
                    }
                }
                if !family.unsupported {
                    Section {
                        HStack(spacing: 12) {
                            if let me = family.current { MemberAvatar(member: me, size: 44) }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(family.current.map { "Jij bent \($0.name)" } ?? "Nog niet gekozen")
                                    .font(.misoButton)
                                    .foregroundStyle(Color.misoBlue)
                                if let me = family.current {
                                    Text(me.role.title).font(.misoCaption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button("Wissel") { showWho = true }
                                .font(.misoButton)
                                .frame(minHeight: 44)
                        }
                        .accessibilityElement(children: .combine)
                        if family.isParent {
                            NavigationLink {
                                MembersEditorView()
                            } label: {
                                Label("Gezinsleden", systemImage: "person.3")
                                    .font(.misoButton)
                                    .foregroundStyle(Color.misoBlue)
                                    .frame(minHeight: 44)
                            }
                            .accessibilityHint("Namen en rol (ouder of kind)")
                        }
                    } header: { Text("Wie ben jij?").misoSectionHeader() }
                    .misoRow()
                }
                if family.isParent {
                    HouseholdSettingsSection(settings: planSettings.settings, errorText: planSettings.errorText,
                                             onHouseholdSize: setHouseholdSize, onOrderWeekday: setOrderWeekday)
                    ReminderSettingsSection()
                }
                Section {
                    Picker("Weergave", selection: $appearance) {
                        ForEach(Appearance.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(minHeight: 44)
                } header: { Text("Weergave").misoSectionHeader() }
                .misoRow()
                if family.isParent {
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
                            ReviewView()
                        } label: {
                            Label("Recepten opruimen", systemImage: "archivebox")
                                .font(.misoButton)
                                .foregroundStyle(Color.misoBlue)
                                .frame(minHeight: 44)
                        }
                        .accessibilityHint("Recepten die jullie nooit of al lang niet kiezen")
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
                }
                Section {
                    Text(session.serverURL).font(.misoBody)
                    Button("Uitloggen", role: .destructive, action: logout)
                        .frame(minHeight: 44)
                } header: { Text("Server").misoSectionHeader() }
                .misoRow()
                if family.isParent {
                    Section {
                        if family.ahConnected == false {
                            Label("AH is nog niet gekoppeld", systemImage: "exclamationmark.triangle")
                                .font(.misoButton)
                                .foregroundStyle(Color.misoBlue)
                        } else if family.ahConnected == true {
                            Label("AH is gekoppeld", systemImage: "checkmark.circle")
                                .font(.misoButton)
                                .foregroundStyle(Color.misoBlue)
                        }
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
            }
            .misoScreen()
            .navigationTitle("Meer")
            .sheet(isPresented: $showWho) { WhoView(asSheet: true) }
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
