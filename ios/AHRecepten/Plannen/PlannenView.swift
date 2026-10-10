import SwiftUI

/// Plannen (zoals /plannen): wensen per dag → voorstel → één knop naar weekmenu en AH-lijstje.
/// "Zelf recepten kiezen" opent de oude Wat eten we?-flow (ook Allerhande en bonus).
struct PlannenView: View {
    @Environment(Session.self) private var session
    @Environment(AppRouter.self) private var router
    @State private var model = PlannenModel()
    @State private var showKiezen = false
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
                        if let error = model.loadError {
                            ErrorBanner(message: error)
                        }
                        switch model.step {
                        case .wishes: wishesStep
                        case .proposal: proposalStep
                        }
                    }
                    .padding(16)
                }
                .onChange(of: model.step) { scrollTop(proxy) }
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.misoCream)
            .navigationTitle("Plannen")
            .safeAreaInset(edge: .bottom) { bottomBar }
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
            .onChange(of: router.planVersion) {
                guard model.step == .wishes else { return }
                Task { await reload() }
            }
            .sheet(isPresented: $showKiezen, onDismiss: kiezenClosed) {
                KiezenView(onClose: closeKiezen)
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
            WishDayRow(day: day, wish: $model[wish: day.date], focus: $focus)
        }
        if !model.weekendDays.isEmpty {
            DisclosureGroup(isExpanded: $model.showWeekend) {
                VStack(spacing: 14) {
                    ForEach(model.weekendDays) { day in
                        WishDayRow(day: day, wish: $model[wish: day.date], focus: $focus)
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
            }
            if let outcome = model.applyOutcome {
                ApplyResultCard(outcome: outcome, onShowWeek: showWeekmenu, onDone: finish)
            }
            ForEach(selection.days) { day in
                ProposalDayCard(day: day, chosen: selection.chosen(for: day),
                                alternatives: selection.alternatives(for: day)) { index in
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
                if model.emptyOpenWeekdays > 0 && !model.collected.isEmpty {
                    Button("Lege doordeweekse dagen: Geen idee", action: fillRest)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(Color.misoBlue)
                        .frame(minHeight: 44)
                }
                Button(action: propose) {
                    if model.proposing {
                        HStack(spacing: 8) { ProgressView(); Text("Miso zoekt recepten…") }
                    } else {
                        Text(proposeTitle)
                    }
                }
                .buttonStyle(.misoPrimary)
                .disabled(model.proposing || model.days.isEmpty || model.openDays.isEmpty)
            case .proposal:
                if model.applyOutcome?.success != true {
                    Button(action: apply) {
                        if model.applying {
                            HStack(spacing: 8) { ProgressView(); Text("Bezig…") }
                        } else {
                            Text("Zet in weekmenu en op mijn AH-lijstje")
                        }
                    }
                    .buttonStyle(.misoPrimary)
                    .disabled(model.applying || (model.selection?.plannedCount ?? 0) == 0)
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

    private var proposeTitle: String {
        let count = model.collected.count
        if !model.days.isEmpty && model.openDays.isEmpty { return "Alles is al gepland" }
        return count == 0 ? "Stel recepten voor" : "Stel recepten voor (\(plural(count, "dag", "dagen")))"
    }

    // MARK: Acties

    private func start() async {
        guard let api = session.api else { return }
        let requested = router.plannenWeek
        router.plannenWeek = nil
        await model.start(api: api, requested: requested)
    }

    private func reload() async {
        guard let api = session.api else { return }
        await model.reload(api: api)
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

    private func fillRest() {
        withAnimation { model.fillRestWithNoIdea() }
    }

    private func propose() {
        guard let api = session.api else { return }
        focus = nil
        Task { await model.propose(api: api) }
    }

    private func backToWishes() {
        model.backToWishes()
    }

    private func apply() {
        guard let api = session.api else { return }
        Task {
            if await model.apply(api: api) {
                router.planChanged()
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

    private func showWeekmenu() {
        router.tab = .plan
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
