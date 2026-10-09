import SwiftUI

// "Wat eten we?": recepten kiezen -> inplannen -> boodschappen.
// Spiegelt backend/app/templates/kiezen.html (zelfde endpoints, payloads en samenvoeg-logica).
// Er wordt nooit een AH-bestelling geplaatst: alleen lijstje vullen en mandje vullen/leegmaken.

// MARK: - Model

struct PickItem: Identifiable, Hashable {
    enum Kind: Hashable { case own, ah }
    /// "own:<id>" of "ah:<allerhande-id>"
    let key: String
    let kind: Kind
    let id: Int
    let name: String
    let imageUrl: String
    let meta: String

    static func own(_ r: RecipeSummary) -> PickItem {
        PickItem(key: "own:\(r.id)", kind: .own, id: r.id, name: r.name, imageUrl: r.imageUrl,
                 meta: [r.servings, r.totalTime].filter { !$0.isEmpty }.joined(separator: " · "))
    }

    static func allerhande(_ h: AHRecipeHit) -> PickItem {
        var meta = [h.time ?? "", h.servings].filter { !$0.isEmpty }.joined(separator: " · ")
        if h.saved { meta += meta.isEmpty ? "in je recepten" : " · in je recepten" }
        return PickItem(key: "ah:\(h.id)", kind: .ah, id: h.id, name: h.title, imageUrl: h.imageUrl ?? "", meta: meta)
    }
}

struct Assignment: Identifiable {
    var id: Int { recipeId }
    let recipeId: Int
    let name: String
    let imageUrl: String
    /// "YYYY-MM-DD", of "" = niet inplannen
    var day: String
    /// Dag waarop het recept deze week al staat.
    var already: String?
}

enum KiezenRoute: Hashable {
    case plan
    case shop
    case recipe(Int)
}

@Observable
@MainActor
final class KiezenModel {
    var picked: [PickItem] = []
    /// Maandag van de gekozen week (leeg = huidige week, de server bepaalt).
    var week = ""

    func isPicked(_ key: String) -> Bool { picked.contains { $0.key == key } }

    func toggle(_ item: PickItem) {
        if let i = picked.firstIndex(where: { $0.key == item.key }) {
            picked.remove(at: i)
        } else {
            picked.append(item)
        }
    }

    var ownIDs: [Int] { picked.filter { $0.kind == .own }.map(\.id) }

    /// Gekozen Allerhande-recepten eerst in de eigen bibliotheek zetten (POST /api/allerhande/add, form recipe_id).
    /// Geeft de mislukte recepten terug als "naam: fout".
    func importAllerhande(api: API, progress: @escaping @MainActor (Int, Int) -> Void) async -> [String] {
        let todo = picked.filter { $0.kind == .ah }
        guard !todo.isEmpty else { return [] }
        var done = 0
        var failed: [String] = []
        progress(0, todo.count)
        await withTaskGroup(of: (PickItem, Result<Int, Error>).self) { group in
            for item in todo {
                group.addTask {
                    do {
                        let r = try await api.addAllerhande(id: item.id)
                        if r.ok, let id = r.id { return (item, .success(id)) }
                        return (item, .failure(APIError(message: r.error ?? "mislukt")))
                    } catch {
                        return (item, .failure(error))
                    }
                }
            }
            for await (item, result) in group {
                done += 1
                progress(done, todo.count)
                switch result {
                case .success(let id):
                    let own = PickItem(key: "own:\(id)", kind: .own, id: id, name: item.name,
                                       imageUrl: item.imageUrl, meta: item.meta)
                    if let i = picked.firstIndex(where: { $0.key == item.key }) {
                        if isPicked(own.key) { picked.remove(at: i) } else { picked[i] = own }
                    }
                case .failure(let error):
                    failed.append("\(item.name): \(error.localizedDescription)")
                }
            }
        }
        return failed
    }

    func reset() {
        picked = []
        week = ""
    }
}

// MARK: - Datums

enum KiezenDates {
    private static let days = ["Maandag", "Dinsdag", "Woensdag", "Donderdag", "Vrijdag", "Zaterdag", "Zondag"]
    private static let months = ["jan", "feb", "mrt", "apr", "mei", "jun", "jul", "aug", "sep", "okt", "nov", "dec"]
    private static var calendar: Calendar { Calendar(identifier: .gregorian) }

    static func parse(_ s: String) -> Date? {
        let p = s.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }

    static func iso(_ d: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static var today: String { iso(Date()) }

    static func add(_ s: String, _ n: Int) -> String {
        guard let d = parse(s), let r = calendar.date(byAdding: .day, value: n, to: d) else { return s }
        return iso(r)
    }

    /// "Maandag 6 okt"
    static func label(_ s: String) -> String {
        guard let d = parse(s) else { return s }
        let c = calendar.dateComponents([.weekday, .day, .month], from: d)
        let weekday = ((c.weekday ?? 2) + 5) % 7
        return "\(days[weekday]) \(c.day ?? 0) \(months[(c.month ?? 1) - 1])"
    }

    /// "6 okt"
    static func short(_ s: String) -> String {
        label(s).split(separator: " ").dropFirst().joined(separator: " ")
    }
}

// MARK: - Gedeelde onderdelen

/// Receptfoto die de breedte van de kaart vult (4:3).
struct CardImage: View {
    @Environment(Session.self) private var session
    let path: String

    private var placeholder: some View {
        Image("Miso/hungry").resizable().scaledToFit().padding(18)
    }

    var body: some View {
        Color.misoLilac.opacity(0.5)
            .aspectRatio(4 / 3, contentMode: .fit)
            .overlay {
                if let url = session.api?.imageURL(path) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            placeholder
                        }
                    }
                } else {
                    placeholder
                }
            }
            .clipped()
            .accessibilityHidden(true)
    }
}

/// Balk onderin met teller en hoofdknop.
struct KiezenBar<Leading: View>: View {
    let title: String
    var enabled = true
    var busy = false
    let action: () -> Void
    @ViewBuilder var leading: Leading

    var body: some View {
        HStack(spacing: 12) {
            leading
            Button(action: action) {
                if busy { ProgressView().tint(Color.misoInk) } else { Text(title).lineLimit(1).minimumScaleFactor(0.8) }
            }
            .buttonStyle(.misoPrimary)
            .disabled(!enabled || busy)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

// MARK: - Stap 1: kiezen

struct KiezenView: View {
    @Environment(Session.self) private var session
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

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !model.picked.isEmpty { pickedChips }
                    ownSection
                    ahSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .scrollDismissesKeyboard(.immediately)
            .background(Color.misoCream)
            .navigationTitle("Wat eten we?")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Zoek: pasta, curry, stamppot...")
            .task(id: query) { await search() }
            .refreshable { await search(debounce: false) }
            .safeAreaInset(edge: .bottom) { bar }
            .alert("Niet gelukt om op te halen", isPresented: Binding(
                get: { importError != nil }, set: { if !$0 { importError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importError ?? "")
            }
            .navigationDestination(for: KiezenRoute.self) { route in
                switch route {
                case .plan: KiezenPlanView { path.append(.shop) }
                case .shop: KiezenShopView { restart() }
                case .recipe(let id): RecipeDetailView(recipeID: id)
                }
            }
        }
        .environment(model)
    }

    // MARK: Onderdelen

    private var pickedChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.picked) { item in
                    Button { withAnimation { model.toggle(item) } } label: {
                        HStack(spacing: 4) {
                            Text(item.name).lineLimit(1)
                            Image(systemName: "xmark").font(.caption2.weight(.bold))
                        }
                        .misoChip(.misoLilac)
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(item.name) weghalen")
                }
            }
        }
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
        KiezenBar(title: "Plan in", enabled: !model.picked.isEmpty, busy: importProgress != nil, action: {
            Task { await planIn() }
        }, leading: {
            Text(importProgress ?? (model.picked.isEmpty ? "Nog niets gekozen" : "\(model.picked.count) gekozen"))
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Color.misoBlue)
                .fixedSize()
                .contentTransition(.numericText())
                .accessibilityAddTraits(.updatesFrequently)
        })
    }

    // MARK: Acties

    @MainActor
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

    @MainActor
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

    @MainActor
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

    @MainActor
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
        }
    }

    private func restart() {
        model.reset()
        query = ""
        path = []
    }
}

struct PickCard: View {
    let item: PickItem
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                CardImage(path: item.imageUrl)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(Color.misoBlue)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if !item.meta.isEmpty {
                        Text(item.meta).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
            }
            .background(Color.misoCard)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(selected ? Color.misoOrange : Color.misoBlue.opacity(0.08), lineWidth: selected ? 3 : 1)
            }
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Color.misoInk)
                        .frame(width: 32, height: 32)
                        .background(Color.misoOrange, in: Circle())
                        .overlay(Circle().stroke(Color.misoCard, lineWidth: 2))
                        .padding(8)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .shadow(color: Color.misoInk.opacity(0.08), radius: 6, x: 0, y: 2)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.meta.isEmpty ? item.name : "\(item.name), \(item.meta)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(selected ? "Tik om niet meer te kiezen" : "Tik om te kiezen")
    }
}

// MARK: - Stap 2: inplannen

struct KiezenPlanView: View {
    @Environment(Session.self) private var session
    @Environment(KiezenModel.self) private var model
    let onNext: () -> Void

    @State private var dates: [String] = []
    @State private var weekPlan: [String: [RecipeSummary]] = [:]
    @State private var assign: [Assignment] = []
    @State private var loading = false
    @State private var loaded = false
    @State private var saving = false
    @State private var errorText: String?

    private let today = KiezenDates.today
    private var hasDays: Bool { assign.contains { !$0.day.isEmpty } }

    var body: some View {
        List {
            Section {
                HStack {
                    Button { Task { await load(KiezenDates.add(model.week, -7)) } } label: {
                        Image(systemName: "chevron.left").frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Vorige week")
                    Spacer()
                    Text(model.week.isEmpty ? "Week" : "Week van \(KiezenDates.short(model.week))")
                        .font(.misoHeadline).foregroundStyle(Color.misoBlue)
                    Spacer()
                    Button { Task { await load(KiezenDates.add(model.week, 7)) } } label: {
                        Image(systemName: "chevron.right").frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Volgende week")
                }
                .buttonStyle(.borderless)
                .disabled(model.week.isEmpty || loading)
                .misoRow()
            } footer: {
                Text("Miso zet je keuze op de eerste vrije dagen. Kies zelf een andere dag als dat beter past.")
            }

            if let errorText {
                ErrorStateView(message: errorText).listRowBackground(Color.clear)
            } else if loading && dates.isEmpty {
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
            } else {
                ForEach(dates, id: \.self) { day in
                    let existing = weekPlan[day] ?? []
                    let mine = assign.filter { $0.day == day }
                    if !(day < today && existing.isEmpty && mine.isEmpty) {
                        Section {
                            ForEach(Array(existing.enumerated()), id: \.offset) { _, r in
                                HStack {
                                    Text(r.name).foregroundStyle(.secondary)
                                    Spacer()
                                    Text("al gepland").misoChip(.misoLilac)
                                }
                                .frame(minHeight: 32)
                                .accessibilityElement(children: .combine)
                            }
                            ForEach(mine) { a in assignRow(a) }
                            if existing.isEmpty && mine.isEmpty {
                                Text("Nog niets").foregroundStyle(.secondary)
                            }
                        } header: {
                            HStack {
                                Text(KiezenDates.label(day)).misoSectionHeader()
                                if day == today { Text("vandaag").misoChip(.misoOrange) }
                            }
                        }
                        .misoRow()
                    }
                }
                let loose = assign.filter { $0.day.isEmpty }
                if !loose.isEmpty {
                    Section {
                        ForEach(loose) { a in assignRow(a) }
                    } header: {
                        Text("Niet (opnieuw) inplannen").misoSectionHeader()
                    } footer: {
                        Text("Komen wel in je boodschappen bij de volgende stap.")
                    }
                    .misoRow()
                }
            }
        }
        .misoScreen()
        .navigationTitle("Inplannen")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            KiezenBar(title: hasDays ? "Opslaan en verder" : "Verder naar boodschappen",
                      enabled: loaded && !assign.isEmpty, busy: saving, action: {
                Task { await saveAndContinue() }
            }, leading: { EmptyView() })
        }
        .task {
            if !loaded { await load(model.week.isEmpty ? nil : model.week) }
        }
    }

    private func assignRow(_ a: Assignment) -> some View {
        HStack(spacing: 12) {
            RecipeImage(path: a.imageUrl, size: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(a.name)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color.misoBlue)
                    .lineLimit(2)
                if let already = a.already, a.day.isEmpty {
                    Text("staat al op \(KiezenDates.label(already).lowercased())").font(.caption).foregroundStyle(.secondary)
                }
                Picker("Dag voor \(a.name)", selection: dayBinding(a.recipeId)) {
                    ForEach(dates, id: \.self) { d in Text(KiezenDates.label(d)).tag(d) }
                    Text("Niet inplannen").tag("")
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(Color.misoOrange)
                .fixedSize()
                .accessibilityLabel("Dag voor \(a.name)")
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private func dayBinding(_ recipeId: Int) -> Binding<String> {
        Binding(
            get: { assign.first { $0.recipeId == recipeId }?.day ?? "" },
            set: { value in
                if let i = assign.firstIndex(where: { $0.recipeId == recipeId }) {
                    withAnimation { assign[i].day = value }
                }
            }
        )
    }

    @MainActor
    private func load(_ start: String?) async {
        guard let api = session.api else { return }
        loading = true
        defer { loading = false }
        do {
            let result = try await api.week(start)
            model.week = result.week
            dates = result.days.map(\.date)
            weekPlan = Dictionary(uniqueKeysWithValues: result.days.map { ($0.date, $0.recipes) })
            errorText = nil
            autoAssign()
            loaded = true
        } catch {
            errorText = "Weekmenu ophalen mislukt. \(error.localizedDescription)"
        }
    }

    /// Eerste lege dag vanaf vandaag; zijn die op, dan de rustigste dag. Zelfde regels als de web-versie.
    private func autoAssign() {
        let start = dates.firstIndex(of: today) ?? 0
        let usable = Array(dates[start...])
        var load = Dictionary(uniqueKeysWithValues: dates.map { ($0, weekPlan[$0]?.count ?? 0) })
        assign = model.picked.filter { $0.kind == .own }.map { p in
            if let already = dates.first(where: { d in (weekPlan[d] ?? []).contains { $0.id == p.id } }) {
                return Assignment(recipeId: p.id, name: p.name, imageUrl: p.imageUrl, day: "", already: already)
            }
            let day = usable.first { load[$0] == 0 }
                ?? usable.min { (load[$0] ?? 0) < (load[$1] ?? 0) } ?? ""
            if !day.isEmpty { load[day, default: 0] += 1 }
            return Assignment(recipeId: p.id, name: p.name, imageUrl: p.imageUrl, day: day)
        }
    }

    @MainActor
    private func saveAndContinue() async {
        guard let api = session.api else { return }
        // Niets op een dag gezet: het weekmenu blijft gelijk, dus opslaan is niet nodig.
        guard hasDays else { onNext(); return }
        var days: [String: [Int]] = [:]
        for d in dates { days[d] = (weekPlan[d] ?? []).map(\.id) }
        for a in assign where !a.day.isEmpty { days[a.day, default: []].append(a.recipeId) }
        saving = true
        defer { saving = false }
        do {
            let result = try await api.savePlan(week: model.week, days: days)
            if result.ok { onNext() } else { errorText = "Opslaan mislukt." }
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// MARK: - Stap 3: boodschappen

struct ShopProduct: Identifiable {
    let id: Int
    let name: String
    let size: String
    let image: String
    var qty: Int
    var recipes: [String]
}

struct ShopLine: Identifiable {
    let id = UUID()
    let text: String
    let recipeId: Int
    let recipeName: String
}

struct KiezenShopView: View {
    @Environment(Session.self) private var session
    @Environment(KiezenModel.self) private var model
    @Environment(\.openURL) private var openURL
    let onRestart: () -> Void

    @State private var loaded = false
    @State private var status: String?
    @State private var products: [ShopProduct] = []
    @State private var unmatched: [ShopLine] = []
    @State private var pantry: [ShopLine] = []
    @State private var recipeCount = 0
    @State private var productCount = 0
    @State private var linkURL: URL?
    @State private var result: (ok: Bool, text: String)?
    @State private var busy: String?
    @State private var confirmClear = false
    @State private var basketLabel: String?  // alleen gezet als er een actieve AH-bestelling is
    @State private var showPantry = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    MascotView(pose: result?.ok == true ? "celebrate" : "groceries", size: 84)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Boodschappen").font(.misoTitle2).foregroundStyle(Color.misoBlue)
                        Text(subtitle).font(.misoCaption).foregroundStyle(.secondary)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .accessibilityElement(children: .combine)

                if let result { resultBanner(result) }
                if let status {
                    HStack(spacing: 8) {
                        if !loaded { ProgressView() }
                        Text(status).font(.misoCaption).foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }

            if !products.isEmpty {
                Section {
                    ForEach(products) { productRow($0) }
                } header: {
                    Text("Producten").misoSectionHeader()
                }
                .misoRow()
            }

            if !unmatched.isEmpty {
                Section {
                    ForEach(unmatched) { u in
                        NavigationLink(value: KiezenRoute.recipe(u.recipeId)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(u.text)
                                Text(u.recipeName).font(.caption).foregroundStyle(Color.misoOrange)
                            }
                            .frame(minHeight: 44, alignment: .leading)
                        }
                        .accessibilityHint("Opent het recept om een product te kiezen")
                    }
                } header: {
                    Text("Nog geen AH-product").misoSectionHeader()
                } footer: {
                    Text("Kies in het recept een product, of vink het ingrediënt uit.")
                }
                .misoRow()
            }

            if !pantry.isEmpty {
                Section {
                    DisclosureGroup(isExpanded: $showPantry) {
                        ForEach(pantry) { p in
                            Text("\(p.text) \(Text("· \(p.recipeName)").foregroundStyle(.secondary))")
                                .font(.callout)
                        }
                    } label: {
                        HStack {
                            Text("Heb je al").font(.misoHeadline).foregroundStyle(Color.misoBlue)
                            Text("\(pantry.count)").misoChip(.misoMint)
                        }
                    }
                    .tint(Color.misoBlue)
                }
                .misoRow()
            }

            if loaded { actions }
        }
        .misoScreen()
        .navigationTitle("Boodschappen")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            KiezenBar(title: productCount > 0 ? "Zet \(productCount) op mijn AH-lijstje" : "Zet op mijn AH-lijstje",
                      enabled: loaded && productCount > 0 && busy == nil, busy: busy == "sync", action: {
                Task { await syncList() }
            }, leading: { EmptyView() })
        }
        .confirmationDialog("Mandje leegmaken?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Haal weg wat Miso erin zette", role: .destructive) { Task { await clearBasket() } }
            Button("Annuleer", role: .cancel) {}
        } message: {
            Text("Haal alles weg wat Miso in je AH-mandje zette? De rest van je mandje blijft staan.")
        }
        .task { if !loaded { await load() } }
        .refreshable { await load() }
    }

    private var subtitle: String {
        if !loaded {
            let n = model.ownIDs.count
            return "\(n) \(n == 1 ? "recept" : "recepten")"
        }
        return "\(productCount) \(productCount == 1 ? "product" : "producten") voor \(recipeCount) \(recipeCount == 1 ? "recept" : "recepten")"
    }

    private func resultBanner(_ r: (ok: Bool, text: String)) -> some View {
        HStack(spacing: 12) {
            MascotView(pose: r.ok ? "celebrate" : "surprised", size: 56)
            Text(r.text).font(.callout).foregroundStyle(Color.misoInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(r.ok ? Color.misoMint : Color.misoOrange.opacity(0.35),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        .accessibilityElement(children: .combine)
    }

    private func productRow(_ p: ShopProduct) -> some View {
        HStack(spacing: 12) {
            Group {
                if let url = session.api?.imageURL(p.image) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image { image.resizable().scaledToFit() } else { Color.misoLilac.opacity(0.4) }
                    }
                } else {
                    Color.misoLilac.opacity(0.4)
                }
            }
            .frame(width: 48, height: 48)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(p.name).font(.system(.subheadline, design: .rounded).weight(.semibold)).foregroundStyle(Color.misoBlue)
                Text((p.size.isEmpty ? "" : "\(p.size) · ") + "voor \(p.recipes.joined(separator: ", "))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Text("\(p.qty)×")
                .font(.system(.headline, design: .rounded).weight(.heavy))
                .foregroundStyle(Color.misoInk)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Color.misoOrange.opacity(0.35), in: Capsule())
        }
        .frame(minHeight: 52)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(p.name), \(p.qty) stuks\(p.size.isEmpty ? "" : ", \(p.size)"), voor \(p.recipes.joined(separator: ", "))")
    }

    private func loadBasketStatus() async {
        guard let api = session.api, let status = try? await api.basketStatus(), status.ok, status.orderId != nil else {
            basketLabel = nil
            return
        }
        if let d = status.delivery, let date = ISO8601DateFormatter.dateOnly.date(from: String(d.prefix(10))) {
            let f = DateFormatter(); f.locale = Locale(identifier: "nl_NL"); f.dateFormat = "EEE d MMM"
            basketLabel = "Zet in mandje voor \(f.string(from: date))"
        } else {
            basketLabel = "Zet in AH-mandje"
        }
    }

    @ViewBuilder
    private var actions: some View {
        Section {
            Color.clear.frame(height: 0).listRowBackground(Color.clear).task { await loadBasketStatus() }
            if let basketLabel {
                Button { Task { await fillBasket() } } label: {
                    if busy == "basket" { ProgressView() } else { Label(basketLabel, systemImage: "basket") }
                }
                .buttonStyle(.misoSecondary)
                .disabled(productCount == 0 || busy != nil)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }

            Button {
                if let linkURL { openURL(linkURL) }
            } label: {
                Label("Open in AH", systemImage: "arrow.up.right.square")
            }
            .buttonStyle(.misoSecondary)
            .disabled(linkURL == nil)
            .accessibilityHint("Opent de producten in de AH-app of op ah.nl")
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))

            Text("Het lijstje krijgt alles van deze week dat er nog niet op stond.")
                .font(.misoCaption).foregroundStyle(.secondary)
                .listRowBackground(Color.clear)

            HStack {
                if basketLabel != nil {
                    Button("Mandje leegmaken", role: .destructive) { confirmClear = true }
                        .disabled(busy != nil)
                }
                Spacer()
                Button("Opnieuw kiezen") { onRestart() }
                    .foregroundStyle(Color.misoBlue)
            }
            .buttonStyle(.borderless)
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .frame(minHeight: 44)
            .listRowBackground(Color.clear)
        }
        .listRowSeparator(.hidden)
    }

    // MARK: Laden en samenvoegen (zelfde logica als kiezen.html)

    @MainActor
    private func load() async {
        guard let api = session.api else { return }
        let ids = model.ownIDs
        loaded = false
        result = nil
        status = "Miso zoekt de beste AH-producten... (0/\(ids.count))"

        // Elk recept laden (de server koppelt automatisch); max 3 tegelijk, want elk recept kan bij AH zoeken.
        var recipes: [RecipeDetail] = []
        var done = 0
        await withTaskGroup(of: RecipeDetail?.self) { group in
            var queue = ids[...]
            func next() {
                guard let id = queue.popFirst() else { return }
                group.addTask { try? await api.recipe(id: id) }
            }
            for _ in 0..<min(3, ids.count) { next() }
            for await r in group {
                if let r { recipes.append(r) }
                done += 1
                status = "Miso zoekt de beste AH-producten... (\(done)/\(ids.count))"
                next()
            }
        }
        recipes.sort { (ids.firstIndex(of: $0.id) ?? 0) < (ids.firstIndex(of: $1.id) ?? 0) }

        // De lijst-link bevat de exacte, samengevoegde aantallen van de server.
        let link = try? await api.listLink(recipeIDs: ids)
        let url = link.flatMap { $0.url.isEmpty ? nil : URL(string: $0.url) }
        var qty: [Int: Int] = [:]
        if let url, let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            for item in items where item.name == "p" {
                let parts = (item.value ?? "").split(separator: ":")
                if parts.count == 2, let pid = Int(parts[0]), let q = Int(parts[1]) { qty[pid] = q }
            }
        }

        var merged: [Int: ShopProduct] = [:]
        var order: [Int] = []
        var missing: [ShopLine] = []
        var have: [ShopLine] = []
        for rec in recipes {
            for ing in rec.ingredients {
                func add(_ pid: Int, _ name: String, _ size: String, _ img: String) {
                    if merged[pid] == nil {
                        merged[pid] = ShopProduct(id: pid, name: name, size: size, image: img, qty: 0, recipes: [])
                        order.append(pid)
                    }
                    merged[pid]?.qty += ing.packs
                    if merged[pid]?.recipes.contains(rec.name) == false { merged[pid]?.recipes.append(rec.name) }
                }
                if ing.skip {
                    have.append(ShopLine(text: ing.text, recipeId: rec.id, recipeName: rec.name))
                    continue
                }
                if let pid = ing.productId {
                    add(pid, ing.product ?? ing.text, ing.unitSize ?? "", ing.productImage ?? "")
                } else {
                    missing.append(ShopLine(text: ing.text, recipeId: rec.id, recipeName: rec.name))
                }
                if let gid = ing.gfProductId {
                    add(gid, (ing.gfProduct ?? "Product") + " (glutenvrij)", "", "")
                }
            }
        }
        var list = order.compactMap { merged[$0] }.filter { qty.isEmpty || qty[$0.id] != nil }
        for i in list.indices { if let q = qty[list[i].id] { list[i].qty = q } }

        products = list
        unmatched = missing
        pantry = have
        linkURL = url
        recipeCount = recipes.count
        productCount = (link?.count ?? 0) > 0 ? (link?.count ?? 0) : list.count
        status = recipes.count < ids.count ? "Niet alle recepten konden worden geladen." : nil
        loaded = true
    }

    // MARK: AH-acties (lijstje/mandje; er wordt nooit iets besteld)

    @MainActor
    private func syncList() async {
        guard let api = session.api, !model.week.isEmpty else { return }
        busy = "sync"
        defer { busy = nil }
        do {
            let r = try await api.syncWeek(model.week, locked: true)
            if r.ok {
                let left = r.status?.unmatched.count ?? 0
                let added = r.added ?? 0
                show(true, (added > 0 ? "\(added) producten op je AH-lijstje gezet." : "Alles stond al op je AH-lijstje.")
                     + " Je weekmenu staat vast." + (left > 0 ? " Nog \(left) ingrediënten zonder AH-product." : ""))
            } else {
                show(false, r.error ?? "Het lijstje vullen is mislukt.")
            }
        } catch {
            show(false, error.localizedDescription)
        }
    }

    @MainActor
    private func fillBasket() async {
        guard let api = session.api else { return }
        busy = "basket"
        defer { busy = nil }
        do {
            let r = try await api.fillBasket(recipeIDs: model.ownIDs)
            if r.ok {
                show(true, "\(r.added ?? 0) producten in je AH-mandje gezet. Afrekenen doe je zelf in de AH-app.")
            } else {
                show(false, r.error ?? "Mandje vullen is mislukt.") // foutmelding van de server letterlijk tonen
            }
        } catch {
            show(false, error.localizedDescription)
        }
    }

    @MainActor
    private func clearBasket() async {
        guard let api = session.api else { return }
        busy = "clear"
        defer { busy = nil }
        do {
            let r = try await api.clearBasket()
            if r.ok {
                let n = r.removed ?? 0
                show(true, n > 0 ? "\(n) producten uit je mandje gehaald." : "Miso had niets in je mandje gezet.")
            } else {
                show(false, r.error ?? "Mandje leegmaken is mislukt.")
            }
        } catch {
            show(false, error.localizedDescription)
        }
    }

    private func show(_ ok: Bool, _ text: String) {
        withAnimation { result = (ok, text) }
        UIAccessibility.post(notification: .announcement, argument: text)
    }
}


extension ISO8601DateFormatter {
    static let dateOnly: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()
}
