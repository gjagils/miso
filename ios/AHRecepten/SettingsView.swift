import SwiftUI

struct SettingsView: View {
    @Environment(Session.self) private var session

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    EmptyStateView(pose: "tech", title: "Miso", message: "Altijd iets lekkers op de planning.", size: 110)
                        .listRowBackground(Color.clear)
                }
                Section { 
                    Text(session.serverURL).font(.misoBody)
                    Button("Uitloggen", role: .destructive) { session.logout() }
                        .frame(minHeight: 44)
                } header: { Text("Server").misoSectionHeader() }
                .misoRow()
                Section {
                    Text("De AH-koppeling stel je eenmalig in op de website van de server, onder Instellingen. Daar plak je de inlogcode van ah.nl.")
                        .font(.callout)
                    if let url = URL(string: session.serverURL + "/settings") {
                        Link("Instellingen op de server openen", destination: url)
                            .font(.misoButton).foregroundStyle(Color.misoBlue)
                            .frame(minHeight: 44)
                    }
                } header: { Text("Albert Heijn").misoSectionHeader() }
                .misoRow()
            }
            .misoScreen()
            .navigationTitle("Meer")
        }
    }
}
