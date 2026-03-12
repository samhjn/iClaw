import SwiftUI

struct ContentView: View {
    @State private var selectedTab: Tab = .sessions

    enum Tab: String {
        case sessions
        case agents
        case skills
        case settings
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            SessionListView()
                .tabItem {
                    Label(L10n.Tabs.sessions, systemImage: "bubble.left.and.bubble.right")
                }
                .tag(Tab.sessions)

            AgentListView()
                .tabItem {
                    Label(L10n.Tabs.agents, systemImage: "cpu")
                }
                .tag(Tab.agents)

            SkillLibraryView()
                .tabItem {
                    Label(L10n.Tabs.skills, systemImage: "sparkles")
                }
                .tag(Tab.skills)

            SettingsView()
                .tabItem {
                    Label(L10n.Tabs.settings, systemImage: "gearshape")
                }
                .tag(Tab.settings)
        }
    }
}
