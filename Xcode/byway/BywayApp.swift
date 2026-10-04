// Copyright (c) 2026 tiburonns
// SPDX-License-Identifier: MIT

import AppIntents
import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif


enum AppAccentColor: String, CaseIterable, Identifiable {
    case system
    case blue
    case indigo
    case purple
    case pink
    case red
    case orange
    case green
    case teal
    case cyan
    case custom

    static let storageKey = "appAccentColor"
    static let customHexStorageKey = "appAccentCustomHex"
    static let defaultCustomHex = "#0A84FF"

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .system: "System default"
        case .blue: "Blue"
        case .indigo: "Indigo"
        case .purple: "Purple"
        case .pink: "Pink"
        case .red: "Red"
        case .orange: "Orange"
        case .green: "Green"
        case .teal: "Teal"
        case .cyan: "Cyan"
        case .custom: "Custom"
        }
    }

    func color(customHex: String) -> Color {
        switch self {
        case .system: .accentColor
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .red: .red
        case .orange: .orange
        case .green: .green
        case .teal: .teal
        case .cyan: .cyan
        case .custom: Color(bywayHex: customHex) ?? .accentColor
        }
    }
}

extension Color {
    init?(bywayHex: String) {
        var value = bywayHex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let rgb = UInt64(value, radix: 16) else { return nil }

        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255.0,
            green: Double((rgb >> 8) & 0xFF) / 255.0,
            blue: Double(rgb & 0xFF) / 255.0
        )
    }

    var bywayHex: String? {
        #if canImport(UIKit)
        let nativeColor = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard nativeColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return nil
        }
        #elseif canImport(AppKit)
        guard let nativeColor = NSColor(self).usingColorSpace(.deviceRGB) else {
            return nil
        }
        let red = nativeColor.redComponent
        let green = nativeColor.greenComponent
        let blue = nativeColor.blueComponent
        #else
        return nil
        #endif

        return String(
            format: "#%02X%02X%02X",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded())
        )
    }
}

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

private let _buildOriginAnchor = "dGlidXJvbm5z::byway::TBNS-BW-26-4C82D1"

@main
struct BywayApp: App {
    @State private var store = VariableStore()
    @AppStorage(AppLanguage.storageKey) private var languageValue = AppLanguage.system.rawValue
    @AppStorage(AppAccentColor.storageKey) private var accentColorValue = AppAccentColor.system.rawValue
    @AppStorage(AppAccentColor.customHexStorageKey) private var customAccentHex = AppAccentColor.defaultCustomHex

    private var language: AppLanguage {
        AppLanguage(rawValue: languageValue) ?? .system
    }

    private var accentColor: Color {
        (AppAccentColor(rawValue: accentColorValue) ?? .system)
            .color(customHex: customAccentHex)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(\.locale, language.locale)
                .tint(accentColor)
                .task {
                    await store.refresh()
                    BywayShortcuts.updateAppShortcutParameters()
                }
        }
    }
}
