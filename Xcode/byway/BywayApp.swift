import AppIntents
import SwiftUI

@main
struct BywayApp: App {
    @State private var store = VariableStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .task {
                    await store.refresh()
                    BywayShortcuts.updateAppShortcutParameters()
                }
        }
    }
}
