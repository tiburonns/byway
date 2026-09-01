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

        AppShortcut(
            intent: AppendEventIntent(),
            phrases: ["Log an event in \(.applicationName)"],
            shortTitle: "Append Event",
            systemImageName: "clock.badge.plus"
        )

        AppShortcut(
            intent: QueryEventsIntent(),
            phrases: ["Query events in \(.applicationName)"],
            shortTitle: "Query Events",
            systemImageName: "line.3.horizontal.decrease.circle"
        )

        AppShortcut(
            intent: GetLastEventIntent(),
            phrases: ["Get the last event from \(.applicationName)"],
            shortTitle: "Last Event",
            systemImageName: "clock.arrow.circlepath"
        )

        AppShortcut(
            intent: GetVariableMetadataIntent(),
            phrases: ["Inspect a variable in \(.applicationName)"],
            shortTitle: "Variable Metadata",
            systemImageName: "info.circle"
        )

        AppShortcut(
            intent: GenerateUUIDIntent(),
            phrases: ["Generate a UUID with \(.applicationName)"],
            shortTitle: "Generate UUID",
            systemImageName: "number.square"
        )

        AppShortcut(
            intent: ExportVariablesIntent(),
            phrases: ["Export variables from \(.applicationName)"],
            shortTitle: "Export Variables",
            systemImageName: "square.and.arrow.up"
        )
    }
}
