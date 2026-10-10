import SwiftUI

/// Het Plannen-tabblad van een kind (zoals plannen_kind.html): "Wat wil jij graag eten, Hannah?".
/// Typen of een favoriet aantikken = wens doorgeven. Niets wissen, plannen of bestellen.
struct KidWishesView: View {
    @Environment(Session.self) private var session
    @Environment(FamilyModel.self) private var family
    @Environment(AppRouter.self) private var router
    @State private var model = KidWishesModel()
    @State private var food = ""
    @State private var grocery = ""
    @FocusState private var focused: Bool

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        MascotView(pose: "heart-eyes", size: 72)
                        Text("Wat wil jij graag eten\(family.current.map { ", \($0.name)" } ?? "")?")
                            .font(.misoTitle2)
                            .foregroundStyle(Color.misoBlue)
                            .accessibilityAddTraits(.isHeader)
                    }
                    wishField(text: $food, prompt: "Bijv. pannenkoeken, iets met wraps",
                              label: "Waar heb je zin in?", button: "Laat het weten", kind: .eten)
                    wishField(text: $grocery, prompt: "Voor de boodschappen: noodles, koekjes…",
                              label: "Iets voor de boodschappen", button: "Zet erbij", kind: .boodschap)
                    if let message = model.message {
                        Text(message)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(Color.misoInk)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.misoMint, in: .rect(cornerRadius: 14))
                    }
                    favoritesSection
                    if !model.myWishes.isEmpty {
                        Text("Al doorgegeven").font(.misoHeadline).foregroundStyle(Color.misoBlue)
                            .accessibilityAddTraits(.isHeader)
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(model.myWishes) { wish in
                                HStack {
                                    Text(wish.ownLine).font(.misoBody).foregroundStyle(Color.misoBlue)
                                    Spacer(minLength: 8)
                                    Button("Haal weg", systemImage: "xmark") { withdraw(wish) }
                                        .labelStyle(.iconOnly)
                                        .foregroundStyle(.secondary)
                                        .frame(minWidth: 44, minHeight: 44)
                                        .buttonStyle(.borderless)
                                        .accessibilityLabel("\(wish.what) weghalen")
                                }
                            }
                        }
                        .misoCard(padding: 12)
                    }
                    Text("Op het menu").font(.misoHeadline).foregroundStyle(Color.misoBlue)
                        .accessibilityAddTraits(.isHeader)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(model.days, id: \.date) { day in
                            HStack(alignment: .firstTextBaseline) {
                                Text(day.date == KiezenDates.today ? "Vandaag" : KiezenDates.label(day.date))
                                    .font(.system(.body, design: .rounded).weight(.bold))
                                    .frame(width: 110, alignment: .leading)
                                VStack(alignment: .leading, spacing: 2) {
                                    if day.items.isEmpty {
                                        Text("nog niks").foregroundStyle(.secondary)
                                    }
                                    ForEach(day.items) { item in
                                        // Tik op een recept: ingrediënten en bereiding (alleen lezen).
                                        if let recipe = item.recipe, item.kind == .recipe {
                                            NavigationLink(value: recipe) {
                                                Text(RecipeDisplayName.short(item.title)).underline()
                                            }
                                            .foregroundStyle(Color.misoBlue)
                                        } else {
                                            Text(RecipeDisplayName.short(item.title)).foregroundStyle(Color.misoBlue)
                                        }
                                    }
                                }
                            }
                            .frame(minHeight: 32)
                        }
                    }
                    .misoCard(padding: 12)
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.misoCream)
            .navigationTitle("Wensen")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: RecipeSummary.self) { RecipeDetailView(recipeID: $0.id) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { MemberAvatarButton() }
            }
            .task { await load() }
            .refreshable { await load() }
            .onChange(of: router.recipesVersion) { Task { await load() } }
        }
    }

    @ViewBuilder private var favoritesSection: some View {
        Text("Jouw favorieten").font(.misoHeadline).foregroundStyle(Color.misoBlue)
            .accessibilityAddTraits(.isHeader)
        if model.favorites.isEmpty && model.loaded {
            Text("Nog geen favorieten. Tik ♥ bij een recept, of kies hieronder iets wat het gezin lekker vindt.")
                .font(.callout).foregroundStyle(.secondary)
        } else {
            Text("Tik er een aan, dan zien papa en mama dat je die graag wilt.")
                .font(.callout).foregroundStyle(.secondary)
            cards(model.favorites, caption: "♥ jouw favoriet")
        }
        if !model.familyFavorites.isEmpty {
            Text("Lekker volgens het gezin").font(.misoHeadline).foregroundStyle(Color.misoBlue)
                .accessibilityAddTraits(.isHeader)
            cards(model.familyFavorites, caption: nil)
        }
    }

    private func cards(_ recipes: [RecipeSummary], caption: String?) -> some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(recipes) { recipe in
                let sent = model.sentRecipeIDs.contains(recipe.id)
                Button {
                    send(WishBody(recipeId: recipe.id))
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        RecipeImage(path: recipe.imageUrl, size: 140)
                            .frame(maxWidth: .infinity)
                        Text(recipe.displayName)
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                            .foregroundStyle(Color.misoBlue)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                        Text(sent ? "✓ doorgegeven" : caption ?? "♥ \(recipe.fansText)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(sent ? Color.misoBlue : Color.misoOrange)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(sent ? Color.misoMint : Color.misoCard, in: .rect(cornerRadius: 18))
                    .contentShape(.rect(cornerRadius: 18))
                }
                .buttonStyle(.plain)
                .disabled(model.sending || sent)
                .accessibilityLabel(recipe.displayName)
                .accessibilityValue(sent ? "doorgegeven" : "")
                .accessibilityHint(sent ? "" : "Geeft door dat je dit graag wilt eten")
            }
        }
    }

    private func wishField(text: Binding<String>, prompt: String, label: String, button: String,
                           kind: WishKind) -> some View {
        HStack(spacing: 8) {
            TextField(prompt, text: text)
                .submitLabel(.send)
                .focused($focused)
                .misoField()
                .accessibilityLabel(label)
                .onSubmit { sendText(text, kind: kind) }
            Button(button) { sendText(text, kind: kind) }
                .buttonStyle(.misoPrimary)
                .fixedSize()
                .disabled(model.sending || text.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func load() async {
        guard let api = session.api else { return }
        await model.load(api: api, me: family.current)
    }

    private func sendText(_ text: Binding<String>, kind: WishKind) {
        let value = text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        guard let api = session.api else { return }
        Task {
            if await model.send(WishBody(text: value, kind: kind), api: api, me: family.current) {
                text.wrappedValue = ""
                focused = false
            }
            announce()
        }
    }

    private func send(_ body: WishBody) {
        guard let api = session.api else { return }
        Task {
            _ = await model.send(body, api: api, me: family.current)
            announce()
        }
    }

    private func withdraw(_ wish: FamilyWish) {
        guard let api = session.api else { return }
        Task { await model.withdraw(wish, api: api, me: family.current) }
    }

    private func announce() {
        if let message = model.message { AccessibilityNotification.Announcement(message).post() }
    }
}
