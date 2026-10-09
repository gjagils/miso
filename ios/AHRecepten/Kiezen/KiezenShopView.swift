import SwiftUI

// MARK: - Stap 3: boodschappen

struct KiezenShopView: View {
    /// Wat er nu met AH gebeurt (lijstje of mandje). Er wordt nooit iets besteld.
    private enum Action { case sync, basket, clear }

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
    @State private var busy: Action?
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
                      enabled: loaded && productCount > 0 && busy == nil, busy: busy == .sync, action: startSync) {
                EmptyView()
            }
        }
        .task { if !loaded { await load() } }
        .refreshable { await load() }
    }

    private var subtitle: String {
        if !loaded {
            return plural(model.ownIDs.count, "recept", "recepten")
        }
        return "\(plural(productCount, "product", "producten")) voor \(plural(recipeCount, "recept", "recepten"))"
    }

    private func resultBanner(_ r: (ok: Bool, text: String)) -> some View {
        HStack(spacing: 12) {
            MascotView(pose: r.ok ? "celebrate" : "surprised", size: 56)
            Text(r.text).font(.callout).foregroundStyle(Color.misoBlue)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(r.ok ? Color.misoMint : Color.misoOrange.opacity(0.35), in: .rect(cornerRadius: 16))
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
            .clipShape(.rect(cornerRadius: 10))
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

    @ViewBuilder
    private var actions: some View {
        Section {
            if let basketLabel {
                Button(action: startFillBasket) {
                    if busy == .basket { ProgressView() } else { Label(basketLabel, systemImage: "basket") }
                }
                .buttonStyle(.misoSecondary)
                .disabled(productCount == 0 || busy != nil)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }

            Button(action: openInAH) {
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
                    Button("Mandje leegmaken", role: .destructive, action: askClearBasket)
                        .disabled(busy != nil)
                        .confirmationDialog("Mandje leegmaken?", isPresented: $confirmClear, titleVisibility: .visible) {
                            Button("Haal weg wat Miso erin zette", role: .destructive, action: startClearBasket)
                            Button("Annuleer", role: .cancel) {}
                        } message: {
                            Text("Haal alles weg wat Miso in je AH-mandje zette? De rest van je mandje blijft staan.")
                        }
                }
                Spacer()
                Button("Opnieuw kiezen", action: onRestart)
                    .foregroundStyle(Color.misoBlue)
            }
            .buttonStyle(.borderless)
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .frame(minHeight: 44)
            .listRowBackground(Color.clear)
        }
        .listRowSeparator(.hidden)
    }

    // MARK: Knoppen

    private func startSync() { Task { await syncList() } }
    private func startFillBasket() { Task { await fillBasket() } }
    private func startClearBasket() { Task { await clearBasket() } }
    private func askClearBasket() { confirmClear = true }
    private func openInAH() {
        if let linkURL { openURL(linkURL) }
    }

    // MARK: Laden en samenvoegen (zelfde logica als kiezen.html)

    private func load() async {
        guard let api = session.api else { return }
        let ids = model.ownIDs
        loaded = false
        result = nil
        status = "Miso zoekt de beste AH-producten... (0/\(ids.count))"

        // Mandje-status tegelijk ophalen; bepaalt of de mandje-knoppen getoond worden.
        async let basket: Void = loadBasketStatus(api)

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
        let persons = model.groceryPersons
        let link = try? await (persons.isEmpty ? api.listLink(recipeIDs: ids) : api.listLink(recipeIDs: ids, persons: persons))
        let url = link.flatMap { $0.url.isEmpty ? nil : URL(string: $0.url) }
        let list = ShoppingListBuilder.build(recipes: recipes,
                                             quantities: ShoppingListBuilder.quantities(fromListLink: url),
                                             linkCount: link?.count ?? 0)
        await basket

        products = list.products
        unmatched = list.unmatched
        pantry = list.pantry
        linkURL = url
        recipeCount = recipes.count
        productCount = list.productCount
        status = recipes.count < ids.count ? "Niet alle recepten konden worden geladen." : nil
        loaded = true
    }

    private func loadBasketStatus(_ api: API) async {
        guard let status = try? await api.basketStatus(), status.ok, status.orderId != nil else {
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

    // MARK: AH-acties (lijstje/mandje; er wordt nooit iets besteld)

    private func syncList() async {
        guard let api = session.api, !model.week.isEmpty else { return }
        busy = .sync
        defer { busy = nil }
        do {
            let r = try await api.syncWeek(model.week, locked: true)
            if r.ok {
                let left = r.status?.unmatched.count ?? 0
                let added = r.added ?? 0
                show(true, (added > 0 ? "\(plural(added, "product", "producten")) op je AH-lijstje gezet." : "Alles stond al op je AH-lijstje.")
                     + " Je weekmenu staat vast."
                     + (left > 0 ? " Nog \(plural(left, "ingrediënt", "ingrediënten")) zonder AH-product." : ""))
            } else {
                show(false, r.error ?? "Het lijstje vullen is mislukt.")
            }
        } catch {
            show(false, error.localizedDescription)
        }
    }

    private func fillBasket() async {
        guard let api = session.api else { return }
        busy = .basket
        defer { busy = nil }
        do {
            let persons = model.groceryPersons
            let r = try await (persons.isEmpty ? api.fillBasket(recipeIDs: model.ownIDs)
                                               : api.fillBasket(recipeIDs: model.ownIDs, persons: persons))
            if r.ok {
                show(true, "\(plural(r.added ?? 0, "product", "producten")) in je AH-mandje gezet. Afrekenen doe je zelf in de AH-app.")
            } else {
                show(false, r.error ?? "Mandje vullen is mislukt.") // foutmelding van de server letterlijk tonen
            }
        } catch {
            show(false, error.localizedDescription)
        }
    }

    private func clearBasket() async {
        guard let api = session.api else { return }
        busy = .clear
        defer { busy = nil }
        do {
            let r = try await api.clearBasket()
            if r.ok {
                let n = r.removed ?? 0
                show(true, n > 0 ? "\(plural(n, "product", "producten")) uit je mandje gehaald." : "Miso had niets in je mandje gezet.")
            } else {
                show(false, r.error ?? "Mandje leegmaken is mislukt.")
            }
        } catch {
            show(false, error.localizedDescription)
        }
    }

    private func show(_ ok: Bool, _ text: String) {
        withAnimation { result = (ok, text) }
        AccessibilityNotification.Announcement(text).post()
    }
}
