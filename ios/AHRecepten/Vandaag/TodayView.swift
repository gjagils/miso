import SwiftUI

/// Vandaag: "Ik ga koken. Wat moet ik doen?" Het gerecht van vandaag groot met "Start met koken",
/// morgen en overmorgen klein eronder (ook over de weekgrens), en de banner voor volgende week.
struct TodayView: View {
    @Environment(Session.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(FamilyModel.self) private var family
    @State private var model = TodayModel()
    @State private var wishText = ""
    @State private var nextWeek = NextWeekModel()
    @State private var cookRecipe: RecipeDetail?
    /// Idee waar je op tikte; eerst bevestigen ("Dit koken we" / "Terug").
    @State private var pendingIdea: TodaySuggestion?
    @State private var confirmingIdea = false
    @State private var startingCook = false
    /// "Verplaats naar morgen" terwijl morgen al iets staat: eerst vragen.
    @State private var pendingMove: PlanItem?
    @State private var confirmingMove = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    if let errorText = model.errorText {
                        ErrorBanner(message: errorText, onDismiss: dismissError)
                    }
                    yesterday
                    tonight
                    if model.loaded {
                        upcoming
                    }
                    QuickWishCard(text: $wishText, sending: model.sendingWish, message: model.wishMessage,
                                  onSend: sendWish)
                    if family.isParent {
                        NextWeekBanner(model: nextWeek, onPlan: planNextWeek)
                    }
                    if model.loaded {
                        if family.isKid {
                            // Kinderen: het menu (alleen lezen) staat bij hun Wensen-tabblad.
                            Button(action: openWishes) {
                                Label("Hele week bekijken", systemImage: "list.bullet.rectangle")
                                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                    .foregroundStyle(Color.misoBlue)
                                    .frame(minHeight: 44)
                            }
                        } else {
                            NavigationLink(value: WeekmenuRoute()) {
                                Label("Hele week bekijken", systemImage: "list.bullet.rectangle")
                                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                    .foregroundStyle(Color.misoBlue)
                                    .frame(minHeight: 44)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Color.misoCream)
            .navigationTitle("Vandaag")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { MemberAvatarButton() }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationDestination(for: RecipeSummary.self) { RecipeDetailView(recipeID: $0.id) }
            .navigationDestination(for: WeekmenuRoute.self) { PlanView(initialWeek: $0.week) }
            .refreshable { await load() }
            .task { await load() }
            // Elders ingepland, of een recept bewerkt/verwijderd: opnieuw ophalen.
            .onChange(of: router.planVersion) { reload() }
            .onChange(of: router.recipesVersion) { reload() }
            .fullScreenCover(item: $cookRecipe) { recipe in
                CookView(recipe: recipe, persons: cookPersons(for: recipe))
            }
            .confirmationDialog(moveTitle, isPresented: $confirmingMove, titleVisibility: .visible,
                                presenting: pendingMove) { item in
                Button("Toch verplaatsen") { move(item) }
                Button("Annuleer", role: .cancel) {}
            } message: { _ in
                Text("Dan staan er morgen twee gerechten. Haal er later eentje weg bij Plannen.")
            }
            .confirmationDialog(ideaTitle, isPresented: $confirmingIdea, titleVisibility: .visible,
                                presenting: pendingIdea) { idea in
                Button("Dit koken we") { plan(idea) }
                Button("Terug", role: .cancel) {}
            } message: { idea in
                switch idea.kind {
                case .recipe: Text("Miso zet het op het menu van vandaag en opent de kookmodus.")
                case .freezer: Text("Miso zet “Iets uit de vriezer” op het menu van vandaag.")
                }
            }
        }
    }

    @ViewBuilder private var tonight: some View {
        if let main = model.mainItem {
            TodayHeroCard(item: main, recipe: model.todayRecipe, starting: startingCook, hints: model.hints,
                          moving: model.moving, alwaysCook: family.isKid, onCook: startCooking,
                          onQuicker: family.isParent ? quicker : nil,
                          onMove: family.isParent && main.isEditable ? { askMove(main) } : nil)
            ForEach(model.otherTodayItems) { item in
                UpcomingDayRow(title: "Ook vandaag", items: [item])
            }
        } else if model.loaded && model.errorText == nil {
            TodaySuggestionsCard(suggestions: model.suggestions, planningID: model.planningSuggestion,
                                 onPick: ask, onPlan: family.isParent ? planToday : nil)
        } else if !model.loaded {
            ProgressView().padding(.top, 40)
        }
    }

    @ViewBuilder private var yesterday: some View {
        let member = session.memberID
        if let thanks = model.yesterdayThanks {
            Text(thanks)
                .font(.callout)
                .foregroundStyle(Color.misoInk)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.misoMint, in: .rect(cornerRadius: 16))
        } else if model.loaded, model.shouldAskYesterday(member: member), let item = model.yesterdayItem {
            YesterdayCard(title: RecipeDisplayName.short(item.title), busy: model.yesterdayBusy,
                          onRate: { rate($0) }, onFavorite: { rate(nil, favorite: true) },
                          onDismiss: { withAnimation { model.dismissYesterday(member: member) } })
        }
    }

    @ViewBuilder private var upcoming: some View {
        ForEach(Array(model.upcoming.enumerated()), id: \.element.date) { offset, day in
            UpcomingDayRow(title: offset == 0 ? "Morgen" : "Overmorgen · \(KiezenDates.label(day.date))",
                           items: day.items)
        }
    }

    private var ideaTitle: String {
        pendingIdea.map { "Vanavond: \($0.title)?" } ?? ""
    }

    private func reload() {
        Task { await load() }
    }

    private func load() async {
        guard let api = session.api else { return }
        async let status: Void = nextWeek.load(api: api)
        await model.load(api: api)
        await status
    }

    // MARK: Acties

    /// Recept al binnen: meteen koken. Anders eerst ophalen (bijv. als dat bij het laden mislukte).
    private func startCooking() {
        if let recipe = model.todayRecipe {
            cookRecipe = recipe
            return
        }
        guard let api = session.api else { return }
        startingCook = true
        Task {
            defer { startingCook = false }
            if let recipe = await model.loadTodayRecipe(api: api) {
                cookRecipe = recipe
            } else {
                model.report("Het recept laden lukte niet. Probeer het nog eens.")
            }
        }
    }

    private func ask(_ idea: TodaySuggestion) {
        pendingIdea = idea
        confirmingIdea = true
    }

    /// Bevestigd: inplannen voor vandaag en (bij een recept) meteen de kookmodus openen.
    private func plan(_ idea: TodaySuggestion) {
        guard let api = session.api else { return }
        Task {
            guard await model.plan(idea, api: api) else { return }
            router.planChanged()
            AccessibilityNotification.Announcement("\(idea.title) staat vandaag op het menu").post()
            if case .recipe = idea.kind, let recipe = model.todayRecipe, !recipe.isByHeart {
                cookRecipe = recipe
            }
        }
    }

    /// Personen voor de kookmodus: zoals gepland (dubbel koken telt mee), anders het recept zelf.
    private func cookPersons(for recipe: RecipeDetail) -> Int? {
        guard let item = model.todayItems.first(where: { $0.recipeId == recipe.id && $0.kind == .recipe }) else { return nil }
        let persons = item.groceryPersons > 0 ? item.groceryPersons : item.persons
        return persons > 0 ? persons : nil
    }

    private func quicker() {
        router.replanDay(model.today, wish: .snel)
    }

    private var moveTitle: String {
        let tomorrow = model.upcoming.first?.items.map { RecipeDisplayName.short($0.title) } ?? []
        return "Morgen staat al \(tomorrow.joined(separator: ", "))"
    }

    private func askMove(_ item: PlanItem) {
        if model.upcoming.first?.items.contains(where: { $0.kind != .leftover || $0.sourceEntryId != item.entryId }) == true {
            pendingMove = item
            confirmingMove = true
        } else {
            move(item)
        }
    }

    private func move(_ item: PlanItem) {
        guard let api = session.api else { return }
        Task {
            if await model.moveToTomorrow(item, api: api) {
                router.planChanged()
                AccessibilityNotification.Announcement("\(item.title) staat nu op morgen").post()
            }
        }
    }

    private func sendWish() {
        guard let api = session.api else { return }
        Task {
            if await model.sendWish(wishText, api: api, isKid: family.isKid) { wishText = "" }
        }
    }

    private func rate(_ rating: TasteRating?, favorite: Bool = false) {
        guard let api = session.api else { return }
        Task {
            await model.rateYesterday(rating, favorite: favorite, member: session.memberID, api: api)
            if favorite { router.recipesChanged() }
        }
    }

    private func openWishes() {
        router.tab = .plannen
    }

    private func dismissError() {
        withAnimation { model.dismissError() }
    }

    private func planToday() {
        router.planWeek(KiezenDates.today)
    }

    private func planNextWeek() {
        router.planWeek(nextWeek.status?.week ?? KiezenDates.add(PlannenLogic.monday(of: KiezenDates.today), 7))
    }
}
