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
                    Label("Sessions", systemImage: "bubble.left.and.bubble.right")
                }
                .tag(Tab.sessions)

            AgentListView()
                .tabItem {
                    Label("Agents", systemImage: "cpu")
                }
                .tag(Tab.agents)

            SkillLibraryView()
                .tabItem {
                    Label("Skills", systemImage: "sparkles")
                }
                .tag(Tab.skills)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(Tab.settings)
        }
    }
}
