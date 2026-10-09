import SwiftUI

@main
struct AHReceptenApp: App {
    @State private var session = Session()

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
            .tint(Color.misoOrange)
            .background(Color.misoCream)
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            WeekOverviewView().tabItem { Label("Vandaag", systemImage: "calendar") }
            // "Wat eten we?" vervangt het oude AH-tabblad: Allerhande zoeken en toevoegen zit nu in deze flow.
            KiezenView().tabItem { Label("Wat eten we?", systemImage: "fork.knife") }
            RecipesView().tabItem { Label("Recepten", systemImage: "book") }
            PlanView().tabItem { Label("Weekmenu", systemImage: "list.bullet.rectangle") }
            SettingsView().tabItem { Label("Meer", systemImage: "gearshape") }
        }
    }
}
