import SwiftUI

@main
struct AHReceptenApp: App {
    @State private var session = Session()
    @State private var router = AppRouter()

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
        }
    }
}

struct RootView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        // iOS 17 is het minimum, dus nog `tabItem` in plaats van de `Tab`-API (iOS 18+).
        TabView(selection: $router.tab) {
            WeekOverviewView()
                .tabItem { Label("Vandaag", systemImage: "calendar") }
                .tag(AppRouter.Tab.today)
            // "Wat eten we?" vervangt het oude AH-tabblad: Allerhande zoeken en toevoegen zit nu in deze flow.
            KiezenView()
                .tabItem { Label("Wat eten we?", systemImage: "fork.knife") }
                .tag(AppRouter.Tab.kiezen)
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
