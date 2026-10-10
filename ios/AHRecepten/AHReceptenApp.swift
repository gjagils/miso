import SwiftUI

@main
struct AHReceptenApp: App {
    @State private var session = Session()
    @State private var router = AppRouter()
    @State private var family = FamilyModel(memberID: Session.defaults.string(forKey: Session.memberKey) ?? "")
    @AppStorage(Appearance.storageKey) private var appearance = Appearance.system

    init() {
        let blue = UIColor(named: "MisoBlue") ?? .label
        let cream = UIColor(named: "MisoCream") ?? .systemBackground
        func rounded(_ style: UIFont.TextStyle, _ weight: UIFont.Weight) -> UIFont {
            let base = UIFont.preferredFont(forTextStyle: style)
            let desc = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
            return UIFont(descriptor: desc.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]]), size: 0)
        }
        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.largeTitleTextAttributes = [.foregroundColor: blue, .font: rounded(.largeTitle, .heavy)]
        nav.titleTextAttributes = [.foregroundColor: blue, .font: rounded(.headline, .bold)]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = cream
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if session.isConnected {
                    RootView()
                } else {
                    ConnectView()
                }
            }
            .environment(session)
            .environment(router)
            .environment(family)
            .tint(Color.misoOrange)
            .background(Color.misoCream)
            .preferredColorScheme(appearance.colorScheme)
            .task { await watchSessionExpiry() }
        }
    }
}

extension AHReceptenApp {
    /// Een 401 op een ingelogde aanvraag (zie `API.sessionExpired`) logt uit, zodat het inlogscherm verschijnt.
    @MainActor
    private func watchSessionExpiry() async {
        for await _ in NotificationCenter.default.notifications(named: API.sessionExpired) {
            session.expire()
        }
    }
}

struct RootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(Session.self) private var session
    @Environment(FamilyModel.self) private var family

    var body: some View {
        Group {
            if family.needsPick {
                // Na het inloggen eerst: wie ben jij? (favorieten, wensen en de kinderweergave horen bij een persoon)
                WhoView()
            } else {
                tabs
            }
        }
        .task(id: session.token) { await loadFamily() }
    }

    private func loadFamily() async {
        family.sync(memberID: session.memberID)
        guard let api = session.api else { return }
        await family.load(api: api)
    }

    @ViewBuilder private var tabs: some View {
        @Bindable var router = router
        // iOS 17 is het minimum, dus nog `tabItem` in plaats van de `Tab`-API (iOS 18+).
        TabView(selection: $router.tab) {
            TodayView()
                .tabItem { Label("Vandaag", systemImage: "fork.knife") }
                .tag(AppRouter.Tab.today)
            // Plannen vervangt "Wat eten we?"; zelf kiezen (ook Allerhande en bonus) zit daar achter een link.
            // Kinderen plannen niet; ze geven door wat ze graag willen eten (zoals /plannen voor een kind).
            Group {
                if family.isKid {
                    KidWishesView()
                } else {
                    PlannenView()
                }
            }
            .tabItem {
                if family.isKid {
                    Label("Wensen", systemImage: "heart.text.square")
                } else {
                    Label("Plannen", systemImage: "calendar.badge.plus")
                }
            }
            .tag(AppRouter.Tab.plannen)
            RecipesView()
                .tabItem { Label("Recepten", systemImage: "book") }
                .tag(AppRouter.Tab.recipes)
            SettingsView()
                .tabItem { Label("Meer", systemImage: "gearshape") }
                .tag(AppRouter.Tab.more)
        }
    }
}
