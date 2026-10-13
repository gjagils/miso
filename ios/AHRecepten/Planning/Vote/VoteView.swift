import SwiftUI

/// Stemronde: iedereen stemt op maximaal drie kandidaten; ouders starten, sluiten en stoppen.
struct VoteView: View {
    @Environment(Session.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(FamilyModel.self) private var family
    /// Week (maandag) waar de ronde bij hoort.
    let week: String
    @State private var model = VoteModel()
    @State private var confirmingStop = false

    var body: some View {
        List {
            if let errorText = model.errorText {
                ErrorBanner(message: errorText, onDismiss: { withAnimation { model.errorText = nil } })
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            if let message = model.message {
                Text(message).font(.misoBody).foregroundStyle(Color.misoBlue).listRowBackground(Color.clear)
            }
            if let poll = model.poll {
                Section {
                    Text(poll.intro).font(.callout).foregroundStyle(.secondary)
                    ForEach(poll.candidates) { candidate in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(candidate.name).font(.system(.body, design: .rounded).weight(.semibold))
                                    .foregroundStyle(Color.misoBlue)
                                Text(candidate.detail).font(.misoCaption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            voteButton(candidate)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Stemronde").misoSectionHeader()
                }
                .misoRow()

                if family.isParent {
                    Section {
                        if poll.open {
                            Button("Sluit en vul de week", action: close).buttonStyle(.misoPrimary).disabled(model.busy)
                            Button("Stop de stemronde") { confirmingStop = true }
                                .buttonStyle(.misoSecondary).disabled(model.busy)
                        } else {
                            Button("Start een stemronde", action: start).buttonStyle(.misoPrimary).disabled(model.busy)
                        }
                    }
                    .misoRow()
                } else if !poll.open {
                    Text("Er loopt nu geen stemronde. Papa of mama kan er een starten.")
                        .font(.callout).foregroundStyle(.secondary).listRowBackground(Color.clear)
                }
            } else if model.errorText == nil {
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
            }
        }
        .misoScreen()
        .navigationTitle("Stemmen")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .confirmationDialog("De stemmen gaan verloren. Doorgaan?", isPresented: $confirmingStop, titleVisibility: .visible) {
            Button("Stop de stemronde", role: .destructive, action: stop)
            Button("Annuleer", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func voteButton(_ candidate: VoteCandidate) -> some View {
        if candidate.mine {
            Button("✓ Mijn stem") { cast(candidate) }
                .buttonStyle(.misoPrimary)
                .fixedSize()
                .disabled(model.busy)
                .accessibilityLabel("Stem op \(candidate.name) weghalen")
        } else {
            Button("Stem") { cast(candidate) }
                .buttonStyle(.misoSecondary)
                .fixedSize()
                .disabled(model.busy)
                .accessibilityLabel("Stem op \(candidate.name)")
        }
    }

    private func load() async {
        guard let api = session.api else { return }
        await model.load(week: week, api: api)
    }

    private func start() {
        guard let api = session.api else { return }
        Task { await model.start(week: week, api: api) }
    }

    private func cast(_ candidate: VoteCandidate) {
        guard let api = session.api else { return }
        Task { await model.cast(candidate, week: week, api: api) }
    }

    private func close() {
        guard let api = session.api else { return }
        Task {
            if await model.close(week: week, api: api) {
                router.planChanged()
                await OrderReminderScheduler.refresh(api: api)
            }
        }
    }

    private func stop() {
        guard let api = session.api else { return }
        Task { await model.cancel(week: week, api: api) }
    }
}
