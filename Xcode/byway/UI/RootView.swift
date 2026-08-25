import SwiftUI

enum AppTab: Hashable {
    case variables
    case history
    case settings
}

struct RootView: View {
    @State private var selectedTab: AppTab = .variables

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                VariableListView()
            }
            .tabItem { Label("Variables", systemImage: "shippingbox.fill") }
            .tag(AppTab.variables)

            NavigationStack {
                HistoryView()
            }
            .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            .tag(AppTab.history)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
            .tag(AppTab.settings)
        }
    }
}
