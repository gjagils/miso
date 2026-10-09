import SwiftUI

struct ConnectView: View {
    @Environment(Session.self) private var session
    @State private var server = ""
    @State private var pin = ""
    @State private var busy = false
    @State private var errorText: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                MascotView(pose: "chef", size: 180).padding(.top, 24)
                VStack(spacing: 6) {
                    MisoWordmark(size: 52)
                    Text("Altijd iets lekkers op de planning.")
                        .font(.misoHeadline)
                        .foregroundStyle(Color.misoBlue)
                        .multilineTextAlignment(.center)
                    Text("Weekmenu. Boodschappen. Samen lekker eten.")
                        .font(.misoBody)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if let reason = session.logoutReason {
                    Label(reason, systemImage: "lock.rotation")
                        .font(.callout)
                        .foregroundStyle(Color.misoInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.misoOrange.opacity(0.35), in: .rect(cornerRadius: 14))
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Waar woont jullie Miso?").font(.misoHeadline).foregroundStyle(Color.misoBlue)
                    Text("Server").font(.misoCaption).foregroundStyle(.secondary)
                    TextField("Server", text: $server, prompt: Text("https://recepten.voorbeeld.nl"))
                        .misoField()
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("Pincode van het gezin").font(.misoCaption).foregroundStyle(.secondary)
                    SecureField("Pincode", text: $pin, prompt: Text("Pincode"))
                        .misoField()
                        .keyboardType(.numberPad)
                    if let errorText {
                        Label(errorText, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(Color.red)
                    }
                    Button(action: startConnect) {
                        if busy { ProgressView().tint(Color.misoInk) } else { Text("Aan de slag") }
                    }
                    .buttonStyle(.misoPrimary)
                    .disabled(server.isEmpty || busy)
                    .padding(.top, 4)
                }
                .misoCard()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color.misoCream.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .onAppear(perform: fillServer)
    }

    private func fillServer() {
        server = session.serverURL
    }

    private func startConnect() {
        Task { await connect() }
    }

    private func connect() async {
        busy = true
        errorText = nil
        defer { busy = false }
        var text = server.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.contains("://") { text = "https://" + text }
        guard let url = URL(string: text) else {
            errorText = "Ongeldig adres"
            return
        }
        do {
            let token = try await API.login(baseURL: url, pin: pin)
            session.serverURL = text
            session.token = token
            session.logoutReason = nil
            session.connected = true
        } catch {
            errorText = error.localizedDescription
        }
    }
}
