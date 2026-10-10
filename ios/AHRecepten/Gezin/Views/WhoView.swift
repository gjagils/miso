import SwiftUI

/// "Wie ben jij?": grote ronde initialen in de kleur van ieder gezinslid. Na het inloggen (zolang er
/// niemand gekozen is) schermvullend; later als blad via de avatar of bij Meer.
struct WhoView: View {
    var asSheet = false
    @Environment(Session.self) private var session
    @Environment(FamilyModel.self) private var family
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 130), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    MascotView(pose: "classic", size: 110)
                    Text("Wie ben jij?")
                        .font(.misoLargeTitle)
                        .foregroundStyle(Color.misoBlue)
                        .accessibilityAddTraits(.isHeader)
                    Text("Dan weet Miso van wie een favoriet of wens is. Dit onthoudt Miso op dit toestel.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    if let error = family.errorText, family.members.isEmpty {
                        ErrorBanner(message: error)
                        Button("Probeer opnieuw", action: retry).buttonStyle(.misoSecondary)
                    } else if family.members.isEmpty {
                        ProgressView().padding(.top, 20)
                    }
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(family.members) { member in
                            Button {
                                choose(member)
                            } label: {
                                VStack(spacing: 10) {
                                    MemberAvatar(member: member, size: 96)
                                    Text(member.name)
                                        .font(.misoHeadline)
                                        .foregroundStyle(Color.misoBlue)
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity)
                                .background(Color.misoCard, in: .rect(cornerRadius: 24))
                                .overlay {
                                    if family.current?.id == member.id {
                                        RoundedRectangle(cornerRadius: 24).strokeBorder(Color.misoOrange, lineWidth: 3)
                                    }
                                }
                                .contentShape(.rect(cornerRadius: 24))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(member.name)
                            .accessibilityAddTraits(family.current?.id == member.id ? .isSelected : [])
                        }
                    }
                    if !asSheet && (family.errorText != nil || family.loaded) {
                        Button("Later", action: skip)
                            .font(.misoButton)
                            .foregroundStyle(Color.misoBlue)
                            .frame(minHeight: 44)
                    }
                }
                .padding(20)
            }
            .background(Color.misoCream)
            .toolbar {
                if asSheet {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Sluit") { dismiss() }
                    }
                }
            }
            .task { if family.members.isEmpty { await load() } }
        }
    }

    private func load() async {
        guard let api = session.api else { return }
        await family.load(api: api)
    }

    private func retry() {
        Task { await load() }
    }

    private func choose(_ member: Member) {
        family.choose(member, session: session)
        // Hartjes, wensen en (kinder)weergave horen bij deze persoon: alles opnieuw laden.
        router.recipesChanged()
        router.planChanged()
        AccessibilityNotification.Announcement("Hoi \(member.name)!").post()
        if asSheet { dismiss() }
    }

    private func skip() {
        family.skip()
    }
}
