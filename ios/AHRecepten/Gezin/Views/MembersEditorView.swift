import SwiftUI

/// Meer → Gezinsleden (alleen ouders): namen en rol (ouder/kind), toevoegen en weghalen.
struct MembersEditorView: View {
    @Environment(Session.self) private var session
    @Environment(FamilyModel.self) private var family
    @Environment(AppRouter.self) private var router
    @State private var drafts: [MemberDraft] = []
    @State private var saving = false
    @State private var message: String?
    @State private var loadedOnce = false

    var body: some View {
        Form {
            Section {
                ForEach($drafts) { $draft in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Naam", text: $draft.name)
                            .textContentType(.givenName)
                            .font(.misoButton)
                            .frame(minHeight: 44)
                        Picker("Rol", selection: $draft.role) {
                            ForEach(MemberRole.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .frame(minHeight: 44)
                    }
                    .accessibilityElement(children: .contain)
                }
                .onDelete { drafts.remove(atOffsets: $0) }
                Button("Gezinslid toevoegen", systemImage: "plus") {
                    drafts.append(MemberDraft(role: .kind))
                }
                .font(.misoButton)
                .frame(minHeight: 44)
            } header: {
                Text("Wie zit er in het gezin?").misoSectionHeader()
            } footer: {
                Text("Een ouder mag alles. Een kind geeft wensen door en zet favorieten, maar wist en bestelt niets. Veeg naar links om iemand weg te halen.")
            }
            .misoRow()
            Section {
                Button(action: save) {
                    if saving { ProgressView() } else { Text("Bewaar") }
                }
                .buttonStyle(.misoPrimary)
                .disabled(saving || !MemberDraft.canSave(drafts))
                .listRowBackground(Color.clear)
                if !MemberDraft.canSave(drafts) {
                    Text("Er moet minstens één ouder met een naam zijn.").font(.callout).foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
                if let message {
                    Text(message).font(.callout).foregroundStyle(Color.misoBlue)
                        .listRowBackground(Color.clear)
                }
            }
        }
        .misoScreen()
        .navigationTitle("Gezinsleden")
        .toolbar { EditButton() }
        .task {
            guard !loadedOnce else { return }
            loadedOnce = true
            drafts = family.members.map(MemberDraft.init)
        }
    }

    private func save() {
        guard let api = session.api else { return }
        saving = true
        Task {
            defer { saving = false }
            do {
                let result = try await api.saveMembers(drafts.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty })
                family.replaceMembers(result.members)
                drafts = result.members.map(MemberDraft.init)
                message = "Bewaard."
                router.recipesChanged()
            } catch {
                message = error.localizedDescription
            }
            if let message { AccessibilityNotification.Announcement(message).post() }
        }
    }
}
