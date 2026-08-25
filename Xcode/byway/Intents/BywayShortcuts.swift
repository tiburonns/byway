import AppIntents

struct BywayShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetVariableIntent(),
            phrases: [
                "Get a variable from \(.applicationName)",
                "Read a \(.applicationName) variable"
            ],
            shortTitle: "Get Variable",
            systemImageName: "arrow.down.circle"
        )

        AppShortcut(
            intent: SetTextVariableIntent(),
            phrases: [
                "Set a variable in \(.applicationName)",
                "Save text in \(.applicationName)"
            ],
            shortTitle: "Set Variable",
            systemImageName: "arrow.up.circle"
        )

        AppShortcut(
            intent: ToggleVariableIntent(),
            phrases: ["Toggle a variable in \(.applicationName)"],
            shortTitle: "Toggle Variable",
            systemImageName: "switch.2"
        )

        AppShortcut(
            intent: IncrementVariableIntent(),
            phrases: ["Increment a variable in \(.applicationName)"],
            shortTitle: "Increment Variable",
            systemImageName: "plus.forwardslash.minus"
        )
    }
}
