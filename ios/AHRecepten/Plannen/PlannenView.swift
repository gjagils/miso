import SwiftUI

/// Plannen (zoals /plannen): wensen per dag → voorstel → één knop naar weekmenu en AH-lijstje.
/// "Zelf recepten kiezen" opent de oude Wat eten we?-flow (ook Allerhande en bonus).
struct PlannenView: View {
    @Environment(Session.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(FamilyModel.self) private var family
    @Environment(\.openURL) private var openURL
    @State private var model = PlannenModel()
    @State private var listStatus = ListStatusModel()
    @State private var showKiezen = false
    @State private var dayToRemove: PlannenDay?
    @State private var confirmingRemove = false
    @FocusState private var focus: String?

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        WeekNavigator(title: model.weekTitle, onPrevious: previousWeek, onNext: nextWeek)
                            .misoCard(padding: 4)
                            .id("top")
                        NavigationLink(value: WeekmenuRoute(week: model.week.isEmpty ? nil : model.week)) {
                            Label("Weekmenu, boodschappen en vriezer van deze week", systemImage: "list.bullet.rectangle")
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .foregroundStyle(Color.misoBlue)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        if let error = model.loadError {
                            ErrorBanner(message: error)
                        }
                        if family.ahConnected == false {
                            Button(action: openSettings) {
                                Label("Koppel AH bij Meer, dan zet Miso de boodschappen op je lijstje.",
                                      systemImage: "link")
                                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                    .foregroundStyle(Color.misoInk)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .padding(.horizontal, 12)
                                    .background(Color.misoLilac, in: .rect(cornerRadius: 14))
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                        if model.step == .wishes && (!model.familyWishes.isEmpty || model.wishMessage != nil) {
                            FamilyWishesSection(wishes: model.familyWishes, days: model.wishTargetDays,
                                                busyID: model.busyWishID, message: model.wishMessage,
                                                onPlace: placeWish, onToList: wishToList, onDone: wishDone,
                                                onDismissMessage: model.dismissWishMessage)
                        }
                        switch model.step {
                        case .wishes: wishesStep
                        case .proposal: proposalStep
                        }
                    }
                    .padding(16)
                }
                .onChange(of: model.step) { scrollTop(proxy) }
                // Uitslag staat bovenaan het voorstel: erheen scrollen, anders zie je hem niet.
                .onChange(of: model.applyOutcome) { scrollTop(proxy) }
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.misoCream)
            .navigationTitle("Plannen")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { MemberAvatarButton() }
            }
            // Tijdens typen geen knoppenbalk boven het toetsenbord: dan zie je het veld niet meer.
            .safeAreaInset(edge: .bottom) { if focus == nil { bottomBar } }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Gereed") { focus = nil }
                }
            }
            .refreshable { await reload() }
            .task { await start() }
            .onChange(of: router.plannenWeek) { _, week in
                guard week != nil else { return }
                Task { await start() }
            }
            .onChange(of: router.plannenRequest) { _, request in
                guard request != nil else { return }
                Task { await start() }
            }
            .onChange(of: model.week) { Task { await loadListStatus() } }
            .onChange(of: router.planVersion) {
                guard model.step == .wishes else { return }
                Task { await reload() }
            }
            .navigationDestination(for: WeekmenuRoute.self) { PlanView(initialWeek: $0.week) }
            .navigationDestination(for: RecipeSummaryLink.self) { RecipeDetailView(recipeID: $0.id) }
            .sheet(isPresented: $showKiezen, onDismiss: kiezenClosed) {
                KiezenView(onClose: closeKiezen)
            }
            .confirmationDialog(removeTitle, isPresented: $confirmingRemove, titleVisibility: .visible,
                                presenting: dayToRemove) { day in
                Button("Haal weg", role: .destructive) { clear(day) }
                Button("Annuleer", role: .cancel) {}
            } message: { day in
                Text("\(day.taken) gaat van het weekmenu af.")
            }
        }
    }

    // MARK: Stap 1: wensen

    @ViewBuilder private var wishesStep: some View {
        @Bindable var model = model
        HStack(spacing: 12) {
            MascotView(pose: "checklist", size: 64)
            Text("Waar hebben jullie zin in? Kies per dag een knop, of zeg het in één zin.")
                .font(.callout)
                .foregroundStyle(Color.misoBlue)
                .fixedSize(horizontal: false, vertical: true)
        }
        SentenceCard(text: $model.sentence, reading: model.readingSentence, message: model.sentenceMessage,
                     focus: $focus, onSubmit: readSentence)
        if model.days.isEmpty && model.loading {
            ProgressView().frame(maxWidth: .infinity).padding(.top, 20)
        }
        ForEach(model.weekdays) { day in
            dayRow(day)
        }
        if model.weekdaysDone && model.collected.isEmpty {
            HStack(spacing: 12) {
                MascotView(pose: "thumbs-up", size: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Maandag tot en met vrijdag staan erin.")
                        .font(.misoHeadline)
                        .foregroundStyle(Color.misoInk)
                    NavigationLink(value: WeekmenuRoute(week: model.week)) {
                        Text("Bekijk weekmenu en boodschappen")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .underline()
                            .foregroundStyle(Color.misoInk)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.misoMint, in: .rect(cornerRadius: 20))
        }
        if !model.weekendDays.isEmpty {
            DisclosureGroup(isExpanded: $model.showWeekend) {
                VStack(spacing: 14) {
                    ForEach(model.weekendDays) { day in
                        dayRow(day)
                    }
                }
                .padding(.top, 10)
            } label: {
                Text("Weekend ook plannen")
                    .font(.misoButton)
                    .foregroundStyle(Color.misoBlue)
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, 4)
        }
        // Na de dagen: hoe staat het met de boodschappen van wat er al gepland is?
        if let status = listStatus.status, status.week == model.week,
           status.showsCard(hasPlanned: model.days.contains { !$0.taken.isEmpty }) {
            ListStatusCard(status: status, syncing: listStatus.syncing, checking: listStatus.checking,
                           message: listStatus.message, onSync: syncList, onCheck: checkList)
        }
        Button(action: openKiezen) {
            Label("Zelf recepten kiezen (ook Allerhande en bonus)", systemImage: "magnifyingglass")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Color.misoBlue)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: Stap 2: voorstel

    @ViewBuilder private var proposalStep: some View {
        if let selection = model.selection {
            VStack(alignment: .leading, spacing: 4) {
                Text("Voorstel")
                    .font(.misoTitle2)
                    .foregroundStyle(Color.misoBlue)
                    .accessibilityAddTraits(.isHeader)
                Text("Tik op een alternatief om te wisselen.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if selection.plannedCount > 0 {
                    Text(selection.weekCheck)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(Color.misoBlue)
                        .padding(.top, 4)
                        .accessibilityLabel("Week-check: \(selection.weekCheck)")
                }
            }
            if let outcome = model.applyOutcome {
                ApplyResultCard(outcome: outcome, week: model.week, onOpenSettings: openSettings, onDone: finish,
                                onCookToday: selection.days.contains { $0.date == KiezenDates.today } ? cookToday : nil)
            }
            ForEach(selection.days) { day in
                ProposalDayCard(day: day, chosen: selection.chosen(for: day),
                                alternatives: selection.alternatives(for: day), fans: model.fans,
                                replacing: selection.replacing.contains(day.date)) { index in
                    withAnimation(.snappy) { model.choose(index, for: day) }
                }
                .disabled(model.applying || model.applyOutcome?.success == true)
            }
        }
    }

    // MARK: Knoppenbalk

    @ViewBuilder private var bottomBar: some View {
        VStack(spacing: 8) {
            switch model.step {
            case .wishes:
                if let message = model.proposeMessage {
                    Text(message).font(.callout).foregroundStyle(Color.misoBlue)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                // Ma-vr staan erin en geen weekendwens: geen knop (de melding staat in de lijst).
                if !(model.weekdaysDone && model.collected.isEmpty) {
                    if model.emptyOpenWeekdays > 0 {
                        // Eén duidelijke knop: lege doordeweekse dagen op "Geen idee", gekozen wensen blijven.
                        Button(action: fillWeek) {
                            if model.proposing {
                                HStack(spacing: 8) { ProgressView(); Text("Miso zoekt recepten…") }
                            } else {
                                Text("Vul de week voor mij")
                            }
                        }
                        .buttonStyle(.misoPrimary)
                        .disabled(model.proposing || model.days.isEmpty)
                        .accessibilityHint("Miso kiest voor de open dagen van maandag tot en met vrijdag; jij wisselt wat je niet wilt")
                        if !model.collected.isEmpty {
                            Button("Alleen de gekozen dagen (\(model.collected.count))", action: propose)
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .foregroundStyle(Color.misoBlue)
                                .frame(minHeight: 44)
                                .disabled(model.proposing)
                        }
                    } else {
                        Button(action: propose) {
                            if model.proposing {
                                HStack(spacing: 8) { ProgressView(); Text("Miso zoekt recepten…") }
                            } else {
                                Text(proposeTitle)
                            }
                        }
                        .buttonStyle(.misoPrimary)
                        .disabled(model.proposing || model.days.isEmpty || model.openDays.isEmpty)
                    }
                }
            case .proposal:
                if model.applyOutcome?.success != true {
                    Button(action: apply) {
                        if model.applying {
                            HStack(spacing: 8) { ProgressView(); Text("Bezig…") }
                        } else {
                            Text(family.ahConnected == false ? "Zet in weekmenu" : "Zet in weekmenu en op mijn AH-lijstje")
                        }
                    }
                    .buttonStyle(.misoPrimary)
                    .disabled(model.applying || (model.selection?.plannedCount ?? 0) == 0)
                    if (model.selection?.plannedCount ?? 0) == 0 {
                        Text("Er is niets om in te plannen. Kies Andere wensen.")
                            .font(.callout)
                            .foregroundStyle(Color.misoBlue)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Button("Andere wensen", action: backToWishes)
                        .buttonStyle(.misoSecondary)
                        .disabled(model.applying)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func dayRow(_ day: PlannenDay) -> some View {
        @Bindable var model = model
        return WishDayRow(day: day, wish: $model[wish: day.date], focus: $focus,
                          onChange: { change(day) }, onRemove: { askRemove(day) },
                          clearing: model.clearingDate == day.date,
                          listBadges: listStatus.status?.week == model.week ? listStatus.status?.entries(on: day.date) ?? [] : [])
    }

    private var removeTitle: String {
        dayToRemove.map { "\($0.label) leegmaken?" } ?? ""
    }

    private var proposeTitle: String {
        let count = model.collected.count
        if !model.days.isEmpty && model.openDays.isEmpty { return "Alles is al gepland" }
        if count == 0 { return "Stel recepten voor" }
        return "Stel recepten voor (\(plural(count, "dag", "dagen")))"
    }

    // MARK: Acties

    private func start() async {
        guard let api = session.api else { return }
        if let request = router.plannenRequest {
            router.plannenRequest = nil
            router.plannenWeek = nil
            await model.handle(request, api: api)
        } else {
            let requested = router.plannenWeek
            router.plannenWeek = nil
            await model.start(api: api, requested: requested)
        }
        await model.loadFamily(api: api)
        await loadListStatus()
    }

    private func reload() async {
        guard let api = session.api else { return }
        await model.reload(api: api)
        await model.loadFamily(api: api)
        await loadListStatus()
    }

    private func loadListStatus() async {
        guard let api = session.api, !model.week.isEmpty, family.ahConnected != false else { return }
        await listStatus.load(api: api, week: model.week)
    }

    private func syncList() {
        guard let api = session.api else { return }
        Task {
            await listStatus.sync(api: api)
            router.planChanged()
        }
    }

    private func checkList() {
        guard let api = session.api else { return }
        Task { await listStatus.check(api: api) }
    }

    private func fillWeek() {
        guard let api = session.api else { return }
        focus = nil
        model.fillRestWithNoIdea()
        Task { await model.propose(api: api) }
    }

    private func placeWish(_ wish: FamilyWish, _ date: String) {
        guard let api = session.api else { return }
        Task {
            if await model.place(wish, on: date, api: api) {
                router.planChanged()
                await loadListStatus()
            }
            if let message = model.wishMessage { AccessibilityNotification.Announcement(message).post() }
        }
    }

    private func wishToList(_ wish: FamilyWish) {
        guard let api = session.api else { return }
        Task {
            if let url = await model.toList(wish, api: api) { openURL(url) }
            await loadListStatus()
        }
    }

    private func wishDone(_ wish: FamilyWish) {
        guard let api = session.api else { return }
        Task { await model.markDone(wish, api: api) }
    }

    private func previousWeek() {
        guard let api = session.api else { return }
        Task { await model.shiftWeek(by: -1, api: api) }
    }

    private func nextWeek() {
        guard let api = session.api else { return }
        Task { await model.shiftWeek(by: 1, api: api) }
    }

    private func readSentence() {
        guard let api = session.api else { return }
        focus = nil
        Task { await model.readSentence(api: api) }
    }

    private func propose() {
        guard let api = session.api else { return }
        focus = nil
        if model.collected.isEmpty { model.fillRestWithNoIdea() }
        Task { await model.propose(api: api) }
    }

    private func backToWishes() {
        model.backToWishes()
    }

    private func apply() {
        guard let api = session.api else { return }
        Task {
            if await model.apply(api: api, syncList: family.ahConnected != false) {
                router.planChanged()
                await loadListStatus()
                await OrderReminderScheduler.refresh(api: api)
            }
            if let message = model.applyOutcome?.message {
                AccessibilityNotification.Announcement(message).post()
            }
        }
    }

    private func finish() {
        guard let api = session.api else { return }
        Task { await model.finish(api: api) }
    }

    /// Vandaag opnieuw gekozen ("Iets snellers"): terug naar Vandaag om te koken.
    private func cookToday() {
        finish()
        router.tab = .today
    }

    private func openSettings() {
        router.tab = .more
    }

    /// Wijzig: de dag opnieuw kiezen. Er wordt nog niets gewist; het oude gaat pas weg als je het nieuwe
    /// bevestigt (replace bij voorstellen en inplannen). Nog eens tikken = "Toch houden".
    private func change(_ day: PlannenDay) {
        let wasReplacing = day.replacing
        withAnimation(.snappy) { model.toggleReplace(day) }
        focus = wasReplacing ? nil : day.date
        AccessibilityNotification.Announcement(wasReplacing ? "\(day.taken) blijft staan."
                                               : "Kies een nieuwe wens voor \(day.label). \(day.taken) blijft tot je bevestigt.").post()
    }

    private func askRemove(_ day: PlannenDay) {
        dayToRemove = day
        confirmingRemove = true
    }

    private func clear(_ day: PlannenDay) {
        guard let api = session.api else { return }
        Task {
            if await model.clear(day, api: api) { router.planChanged() }
        }
    }

    private func openKiezen() {
        router.kiezenWeek = model.week.isEmpty ? nil : model.week
        showKiezen = true
    }

    private func closeKiezen() {
        showKiezen = false
    }

    private func kiezenClosed() {
        Task { await reload() }
    }

    private func scrollTop(_ proxy: ScrollViewProxy) {
        withAnimation { proxy.scrollTo("top", anchor: .top) }
    }
}
