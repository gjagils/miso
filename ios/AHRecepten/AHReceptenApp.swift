import SwiftUI

@main
struct AHReceptenApp: App {
    @State private var session = Session()
    @State private var router = AppRouter()
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

    var body: some View {
        @Bindable var router = router
        // iOS 17 is het minimum, dus nog `tabItem` in plaats van de `Tab`-API (iOS 18+).
        TabView(selection: $router.tab) {
            TodayView()
                .tabItem { Label("Vandaag", systemImage: "fork.knife") }
                .tag(AppRouter.Tab.today)
            // Plannen vervangt "Wat eten we?"; zelf kiezen (ook Allerhande en bonus) zit daar achter een link.
            PlannenView()
                .tabItem { Label("Plannen", systemImage: "calendar.badge.plus") }
                .tag(AppRouter.Tab.plannen)
            RecipesView()
                .tabItem { Label("Recepten", systemImage: "book") }
                .tag(AppRouter.Tab.recipes)
            PlanView()
                .tabItem { Label("Weekmenu", systemImage: "list.bullet.rectangle") }
                .tag(AppRouter.Tab.plan)
            SettingsView()
                .tabItem { Label("Meer", systemImage: "gearshape") }
                .tag(AppRouter.Tab.more)
        }
    }
}
