import SwiftUI

@main
struct LyraApp: App {
    @StateObject private var model = PhoneModel.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            CommandView(model: model)
                .onChange(of: scenePhase) { _, phase in model.isActive = phase == .active }
        }
    }
}

@MainActor
final class PhoneModel: ObservableObject {
    static let shared = PhoneModel()

    @Published var headline = "Tap to speak"
    @Published var detail = ""
    @Published var history: [String] = []
    @Published var isThinking = false
    @Published var pendingKey = ""
    @Published var shortcuts = UserDefaults.standard.string(forKey: "Shortcuts") ?? "" {
        didSet { UserDefaults.standard.set(shortcuts, forKey: "Shortcuts") }
    }
    let speech = PhoneSpeech()
    let wake = WakeWord()
    /// Off by default: it holds the microphone open for as long as the app is in front.
    @Published var wakeWordEnabled = UserDefaults.standard.bool(forKey: "WakeWord") {
        didSet { UserDefaults.standard.set(wakeWordEnabled, forKey: "WakeWord"); syncWake() }
    }
    var hasKey: Bool { Keys.key != nil }

    init() {
        speech.onFinal = { [weak self] text in self?.run(text) }
        wake.onHeard = { [weak self] in
            guard let self else { return }
            headline = "Yes?"
            Task { await self.speech.start() }
        }
    }

    /// Runs the wake listener only when nothing else needs the microphone.
    func syncWake() {
        if wakeWordEnabled && hasKey && !speech.isListening && !isThinking && isActive { wake.start() }
        else { wake.stop() }
    }

    /// iOS takes the microphone away the moment the app leaves the screen, so the wake word goes
    /// with it. There is no always-on listening for a third-party app; Siri is the only one.
    var isActive = true { didSet { syncWake() } }

    func toggle() {
        if speech.isListening { speech.stop() } else { wake.stop(); Task { await speech.start() } }
    }

    func run(_ command: String) {
        isThinking = true
        headline = command
        detail = "Working it out…"
        Task {
            do {
                let action = try await PhoneBrain.decide(command)
                detail = action.say
                if action.kind == .none {
                    headline = "Can't do that on iPhone"
                } else if await action.run() {
                    headline = command
                    history.insert("\(command) → \(action.say)", at: 0)
                } else {
                    headline = "Nothing opened"
                    detail = "\(action.say) — that app or shortcut may not be installed."
                }
            } catch {
                headline = "Stopped"
                detail = error.localizedDescription
            }
            isThinking = false
            syncWake()
        }
    }

    func saveKey() {
        Keys.save(pendingKey)
        pendingKey = ""
        objectWillChange.send()
        syncWake()
    }
}

private struct CommandView: View {
    @ObservedObject var model: PhoneModel
    @ObservedObject private var speech: PhoneSpeech
    @State private var showingSettings = false
    @State private var typed = ""

    init(model: PhoneModel) {
        self.model = model
        self.speech = model.speech
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                Text(speech.isListening && !speech.transcript.isEmpty ? speech.transcript : model.headline)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .animation(.default, value: model.headline)
                if !model.detail.isEmpty {
                    Text(model.detail).font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                if !speech.status.isEmpty {
                    Text(speech.status).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                micButton
                HStack {
                    TextField("Or type a command", text: $typed)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { send() }
                    Button("Run", action: send).disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if !model.history.isEmpty {
                    List(model.history, id: \.self) { line in
                        Text(line).font(.footnote).foregroundStyle(.secondary)
                    }
                    .listStyle(.plain)
                    .frame(maxHeight: 160)
                }
            }
            .padding(24)
            .navigationTitle("Lyra")
            .toolbar {
                Button { showingSettings = true } label: { Image(systemName: "gearshape") }
            }
            .sheet(isPresented: $showingSettings) { SettingsSheet(model: model) }
            .task {
                if !model.hasKey { showingSettings = true } else { model.syncWake() }
            }
        }
        .overlay(alignment: .top) {
            NotchPanel(title: notchTitle, subtitle: notchSubtitle,
                       level: speech.level, isOpen: speech.isListening || model.isThinking)
        }
    }

    private var notchTitle: String {
        if speech.isListening { return speech.transcript.isEmpty ? "Listening…" : speech.transcript }
        return model.headline
    }

    private var notchSubtitle: String {
        speech.isListening ? "Tap the button to send" : model.detail
    }

    private var micButton: some View {
        Button(action: model.toggle) {
            ZStack {
                Circle()
                    .fill(speech.isListening ? Color.red.gradient : Color.teal.gradient)
                    .frame(width: 112, height: 112)
                    .scaleEffect(1 + (speech.isListening ? speech.level * 0.25 : 0))
                    .animation(.easeOut(duration: 0.08), value: speech.level)
                Image(systemName: speech.isListening ? "stop.fill" : "mic.fill")
                    .font(.system(size: 40, weight: .medium)).foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .disabled(model.isThinking)
        .accessibilityLabel(speech.isListening ? "Stop and run" : "Speak a command")
    }

    private func send() {
        let command = typed.trimmingCharacters(in: .whitespaces)
        guard !command.isEmpty else { return }
        typed = ""
        model.run(command)
    }
}

private struct SettingsSheet: View {
    @ObservedObject var model: PhoneModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("OpenRouter key") {
                    SecureField(model.hasKey ? "Key saved — enter a replacement" : "OpenRouter API key",
                                text: $model.pendingKey)
                    Button("Save key") { model.saveKey() }
                        .disabled(model.pendingKey.trimmingCharacters(in: .whitespaces).isEmpty)
                    Text("Kept in this iPhone's Keychain. Your command and your shortcut names are sent to OpenRouter; nothing else is.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Wake word") {
                    Toggle("Listen for “hey Lyra”", isOn: $model.wakeWordEnabled)
                        .disabled(!model.wake.isSupported)
                    Text(model.wake.isSupported
                         ? "On device only — nothing it hears leaves the phone. It works while Lyra is on screen: iOS does not let any app but Siri hold the microphone in the background. For hands-free from anywhere, say “Hey Siri, ask Lyra”."
                         : "This iPhone has no on-device speech model for your language, so the wake word is unavailable.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Your Shortcuts") {
                    TextEditor(text: $model.shortcuts).frame(minHeight: 120)
                    Text("One name per line, exactly as they appear in the Shortcuts app. iOS gives no way to read them, so this list is how Lyra knows what you can run — and running a shortcut is the only way anything real happens in another app.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("What this can and cannot do") {
                    Text("It opens things: a shortcut, an app, a search, a call, a message ready to send, a place in Maps, a link. It cannot tap around inside other apps — iOS does not let any app do that. The Mac app can, which is why it works differently.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}
