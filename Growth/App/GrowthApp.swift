import SwiftUI
import SwiftData

@main
struct GrowthApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(ModelContainerFactory.shared)
    }
}

enum AppTab: Hashable {
    case home
    case goals
    case journal
}

struct RootTabView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var permissions = NotificationPermission()
    @State private var tab: AppTab = .home

    var body: some View {
        TabView(selection: $tab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }
                .tag(AppTab.home)
                .accessibilityIdentifier("tab.home")

            GoalsListView()
                .tabItem { Label("Goals", systemImage: "flag") }
                .tag(AppTab.goals)
                .accessibilityIdentifier("tab.goals")

            JournalListView()
                .tabItem { Label("Journal", systemImage: "book") }
                .tag(AppTab.journal)
                .accessibilityIdentifier("tab.journal")
        }
        .environment(permissions)
        .task {
            await refreshNotifications()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await refreshNotifications() }
        }
    }

    private func refreshNotifications() async {
        await permissions.refresh()
        await NotificationScheduler.reschedule(context: context)
    }
}
