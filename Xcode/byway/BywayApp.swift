import AppIntents
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case spanish = "es"

    static let storageKey = "appLanguage"

    var id: String { rawValue }

    var locale: Locale {
        switch self {
        case .system: .autoupdatingCurrent
        case .english: Locale(identifier: "en")
        case .spanish: Locale(identifier: "es")
        }
    }

    var titleKey: LocalizedStringKey {
        switch self {
        case .system: "System default"
        case .english: "English"
        case .spanish: "Spanish"
        }
    }
}

@main
struct BywayApp: App {
    @State private var store = VariableStore()
    @AppStorage(AppLanguage.storageKey) private var languageValue = AppLanguage.system.rawValue

    private var language: AppLanguage {
        AppLanguage(rawValue: languageValue) ?? .system
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(\.locale, language.locale)
                .task {
                    await store.refresh()
                    BywayShortcuts.updateAppShortcutParameters()
                }
        }
    }
}
