import SwiftUI

// MARK: - Stap 1: kiezen

struct KiezenView: View {
    @Environment(Session.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var model = KiezenModel()
    @State private var path: [KiezenRoute] = []
    @State private var query = ""
    @State private var own: [RecipeSummary] = []
    @State private var ownError: String?
    @State private var ownLoaded = false
    @State private var ahHits: [AHRecipeHit] = []
    @State private var ahStatus: String?
    @State private var ahSearching = false
    @State private var ahSeq = 0
    @State private var importProgress: String?
    @State private var importError: String?
    @State private var showImportError = false
    /// Gezet als Kiezen als blad vanuit Plannen opent: toont een Sluit-knop.
    var onClose: (() -> Void)?

    /// Twee (of meer) kolommen; bij heel grote tekst één kolom zodat titels leesbaar blijven.
    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.adaptive(minimum: 150), spacing: 12)]
    }
    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !model.week.isEmpty {
                        Label("Je plant voor de week van \(KiezenDates.short(model.week))", systemImage: "calendar")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(Color.misoBlue)
                    }
                    if !model.picked.isEmpty { pickedChips }
                    ownSection
                    ahSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .scrollDismissesKeyboard(.immediately)
            .background(Color.misoCream)
            .navigationTitle("Zelf kiezen")
            .toolbar {
                if let onClose {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Sluit", action: onClose)
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Zoek: pasta, curry, stamppot...")
            .task(id: query) { await search() }
            .refreshable { await search(debounce: false) }
            .safeAreaInset(edge: .bottom) { bar }
            .alert("Niet gelukt om op te halen", isPresented: $showImportError, presenting: importError) { _ in
                Button("OK", role: .cancel) {}
            } message: { text in
                Text(text)
            }
            .navigationDestination(for: KiezenRoute.self) { route in
                switch route {
                case .plan: KiezenPlanView(onNext: showShop)
                case .shop: KiezenShopView(onRestart: restart)
                case .recipe(let id): RecipeDetailView(recipeID: id)
                }
            }
        }
        .environment(model)
        .onChange(of: router.kiezenWeek, initial: true) { _, week in
            planRequestedWeek(week)
        }
    }

    /// "Plan volgende week" vanaf Vandaag: begin bij stap 1 voor die week.
    private func planRequestedWeek(_ week: String?) {
        guard let week else { return }
        model.week = week
        path = []
        router.kiezenWeek = nil
    }

    // MARK: Onderdelen

    private var pickedChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(model.picked) { item in
                    Button {
                        unpick(item)
                    } label: {
                        HStack(spacing: 4) {
                            Text(item.name).lineLimit(1)
                            Image(systemName: "xmark").font(.caption2).bold()
                        }
                        .misoChip(.misoLilac)
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(item.name) weghalen")
                }
            }
        }
        .scrollIndicators(.hidden)
        .accessibilityLabel("Gekozen recepten")
    }

    private func header(_ title: String, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.misoTitle2).foregroundStyle(Color.misoBlue)
            if count > 0 { Text("\(count)").misoChip(.misoMint) }
        }
        .padding(.top, 6)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var ownSection: some View {
        if ownLoaded && own.isEmpty && trimmed.isEmpty && ownError == nil {
            EmptyView() // nog geen eigen recepten: sectie verbergen, zoals de web-versie
        } else {
            header("Jouw recepten", count: own.count)
            if let ownError {
                Text(ownError).font(.misoCaption).foregroundStyle(.secondary)
            } else if !ownLoaded {
                ProgressView().frame(maxWidth: .infinity)
            } else if own.isEmpty {
                Text("Geen eigen recepten met \"\(trimmed)\".").font(.misoCaption).foregroundStyle(.secondary)
            } else {
                grid(own.map(PickItem.own))
            }
        }
    }

    @ViewBuilder
    private var ahSection: some View {
        header("Uit Allerhande", count: ahHits.count)
        if trimmed.isEmpty {
            EmptyStateView(pose: "hungry", title: "Waar heb je zin in?",
                           message: "Zoek hierboven een gerecht. Tik op recepten om ze te kiezen, zoveel als je wilt voor de hele week.",
                           size: 110)
        } else if ahSearching {
            HStack(spacing: 8) {
                ProgressView()
                Text("Miso snuffelt in Allerhande...").font(.misoCaption).foregroundStyle(.secondary)
            }
        } else if let ahStatus {
            Text(ahStatus).font(.misoCaption).foregroundStyle(.secondary)
        }
        if !ahHits.isEmpty { grid(ahHits.map(PickItem.allerhande)) }
    }

    private func grid(_ items: [PickItem]) -> some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(items) { item in
                PickCard(item: item, selected: model.isPicked(item.key)) {
                    withAnimation(.snappy(duration: 0.2)) { model.toggle(item) }
                }
            }
        }
    }

    private var bar: some View {
        KiezenBar(title: "Plan in", enabled: !model.picked.isEmpty, busy: importProgress != nil, action: startPlanIn) {
            Text(importProgress ?? (model.picked.isEmpty ? "Nog niets gekozen" : "\(model.picked.count) gekozen"))
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Color.misoBlue)
                .fixedSize()
                .contentTransition(.numericText())
                .accessibilityAddTraits(.updatesFrequently)
        }
    }

    // MARK: Acties

    private func unpick(_ item: PickItem) {
        withAnimation { model.toggle(item) }
    }

    private func startPlanIn() {
        Task { await planIn() }
    }

    private func showShop() {
        path.append(.shop)
    }

    private func search(debounce: Bool = true) async {
        guard let api = session.api else { return }
        let q = trimmed
        if debounce && ownLoaded {
            try? await Task.sleep(for: .milliseconds(300))
            if Task.isCancelled { return }
        }
        async let ownTask: Void = loadOwn(api, q)
        async let ahTask: Void = searchAh(api, q)
        _ = await (ownTask, ahTask)
    }

    private func loadOwn(_ api: API, _ q: String) async {
        do {
            let result = try await api.recipes(query: q)
            if Task.isCancelled { return }
            own = result
            ownError = nil
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { return }
            ownError = error.localizedDescription
        }
        ownLoaded = true
    }

    private func searchAh(_ api: API, _ q: String) async {
        guard q.count >= 2 else {
            ahHits = []
            ahSearching = false
            ahStatus = q.isEmpty ? nil : "Typ nog een letter om in Allerhande te zoeken."
            return
        }
        ahSeq += 1
        let my = ahSeq
        ahSearching = true
        // Ook bij annuleren (bijv. een afgebroken pull-to-refresh) de laadstatus opruimen,
        // tenzij er al een nieuwere zoekopdracht loopt.
        defer { if my == ahSeq { ahSearching = false } }
        do {
            let hits = try await api.searchAllerhande(q)
            if Task.isCancelled || my != ahSeq { return }
            ahHits = hits
            ahStatus = hits.isEmpty ? "Niets gevonden in Allerhande voor \"\(q)\"." : nil
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { return }
            ahHits = []
            ahStatus = error.localizedDescription
        }
    }

    private func planIn() async {
        guard let api = session.api else { return }
        let failed = await model.importAllerhande(api: api) { done, total in
            importProgress = "Recepten ophalen \(done)/\(total)"
        }
        importProgress = nil
        if failed.isEmpty {
            path.append(.plan)
        } else {
            importError = failed.joined(separator: "\n")
            showImportError = true
        }
    }

    private func restart() {
        model.reset()
        query = ""
        path = []
    }
}
