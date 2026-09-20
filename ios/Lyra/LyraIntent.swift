import AppIntents

/// Puts Lyra in Siri, Spotlight and the Shortcuts app: "Hey Siri, Lyra, text Amit I'm running late".
/// The app has to come to the front because everything it does is opening a URL, which only a
/// foreground app may do.
struct RunLyraCommand: AppIntent {
    static var title: LocalizedStringResource = "Run a Lyra command"
    static var description = IntentDescription("Say what you want. Lyra picks the shortcut, app or link that does it.")
    static var openAppWhenRun = true

    @Parameter(title: "Command", requestValueDialog: "What would you like done?")
    var command: String

    @MainActor
    func perform() async throws -> some IntentResult {
        PhoneModel.shared.run(command)
        return .result()
    }
}

struct LyraShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        // Only entity and enum parameters may be spoken inside a phrase, so Siri asks for the
        // command itself through `requestValueDialog`.
        AppShortcut(intent: RunLyraCommand(), phrases: [
            "Ask \(.applicationName)",
            "Run a \(.applicationName) command"
        ], shortTitle: "Run a command", systemImageName: "mic.fill")
    }
}
