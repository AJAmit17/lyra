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
    @Published var pendingTypeSafe = ""
    @Published var pendingOpenRouter = ""
    @Published var shortcuts = UserDefaults.standard.string(forKey: "Shortcuts") ?? "" {
        didSet { UserDefaults.standard.set(shortcuts, forKey: "Shortcuts") }
    }
    let speech = PhoneSpeech()
    let wake = WakeWord()
    /// Off by default: it holds the microphone open for as long as the app is in front.
    @Published var wakeWordEnabled = UserDefaults.standard.bool(forKey: "WakeWord") {
        didSet { UserDefaults.standard.set(wakeWordEnabled, forKey: "WakeWord"); syncWake() }
    }
    var hasTypeSafe: Bool { Keys.read(Keys.typeSafe) != nil }
    var hasOpenRouter: Bool { Keys.read(Keys.openRouter) != nil }
    /// The phone needs the OpenRouter key to do anything; TypeSafe is stored alongside it.
    var hasKey: Bool { hasOpenRouter }

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

    func saveKeys() {
        Keys.save(pendingTypeSafe, account: Keys.typeSafe)
        Keys.save(pendingOpenRouter, account: Keys.openRouter)
        pendingTypeSafe = ""
        pendingOpenRouter = ""
        objectWillChange.send()
        syncWake()
    }
}

private struct CommandView: View {
    @ObservedObject var model: PhoneModel
    @ObservedObject private var speech: PhoneSpeech
    @ObservedObject private var wake: WakeWord
    @State private var showingSettings = false
    @State private var typed = ""
    @FocusState private var typing: Bool

    init(model: PhoneModel) {
        self.model = model
        self.speech = model.speech
        self.wake = model.wake
    }

    private var isOpen: Bool { speech.isListening || model.isThinking }

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.04, blue: 0.07).ignoresSafeArea()

            // A soft pool of light under the button, so the screen has a centre of gravity.
            RadialGradient(colors: [Color.teal.opacity(speech.isListening ? 0.22 : 0.10), .clear],
                           center: .init(x: 0.5, y: 0.78), startRadius: 4, endRadius: 320)
                .ignoresSafeArea()
                .animation(.smooth(duration: 0.4), value: speech.isListening)

            VStack(spacing: 0) {
                header
                Spacer()
                state
                    .padding(.bottom, 34)
                micButton
                Spacer().frame(height: 26)
                history
                controls
            }
            .padding(.horizontal, 20)
        }
        .preferredColorScheme(.dark)
        .overlay {
            IslandPanel(title: notchTitle, subtitle: notchSubtitle, level: speech.level,
                        isListening: speech.isListening, isOpen: isOpen)
        }
        .sheet(isPresented: $showingSettings) { SettingsSheet(model: model) }
        .task { if !model.hasKey { showingSettings = true } else { model.syncWake() } }
    }

    private var header: some View {
        HStack {
            Text("Lyra").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
            if wake.isRunning {
                Label("hey lyra", systemImage: "waveform")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.teal)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(Color.teal.opacity(0.14)))
            }
            Spacer()
            Button { showingSettings = true } label: {
                Image(systemName: "gearshape").font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .padding(.top, 8)
    }

    private var state: some View {
        VStack(spacing: 10) {
            Text(speech.isListening && !speech.transcript.isEmpty ? speech.transcript : model.headline)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
            if !model.detail.isEmpty {
                Text(model.detail)
                    .font(.system(size: 14)).foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
            }
            if !model.hasKey {
                Button("Add your keys") { showingSettings = true }
                    .font(.system(size: 14, weight: .medium))
                    .buttonStyle(.borderedProminent).tint(.teal)
                    .padding(.top, 4)
            }
        }
        .animation(.smooth(duration: 0.25), value: model.headline)
    }

    @ViewBuilder
    private var history: some View {
        if !model.history.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(model.history.prefix(3), id: \.self) { line in
                    Text(line)
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.35))
                        .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.bottom, 14)
            .transition(.opacity)
        }
    }

    private var controls: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                TextField("Type a command", text: $typed)
                    .focused($typing)
                    .submitLabel(.go)
                    .onSubmit(send)
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .background(Capsule().fill(.white.opacity(0.07)))
                    .foregroundStyle(.white)
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(typed.isEmpty ? Color.white.opacity(0.08) : Color.teal))
                        .foregroundStyle(typed.isEmpty ? .white.opacity(0.3) : .white)
                }
                .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.bottom, 12)
    }

    private var micButton: some View {
        Button(action: model.toggle) {
            ZStack {
                Circle()
                    .fill(speech.isListening ? AnyShapeStyle(Color.red.gradient)
                                             : AnyShapeStyle(Color.teal.gradient))
                    .frame(width: 96, height: 96)
                Circle()
                    .stroke(Color.teal.opacity(0.35), lineWidth: 2)
                    .frame(width: 96, height: 96)
                    .scaleEffect(1 + speech.level * 0.5)
                    .opacity(speech.isListening ? 1 - speech.level : 0)
                Image(systemName: speech.isListening ? "stop.fill" : "mic.fill")
                    .font(.system(size: 34, weight: .medium)).foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .disabled(model.isThinking || !model.hasKey)
        .animation(.easeOut(duration: 0.1), value: speech.level)
        .accessibilityLabel(speech.isListening ? "Stop and run" : "Speak a command")
    }

    private var notchTitle: String {
        if speech.isListening { return speech.transcript.isEmpty ? "Listening…" : speech.transcript }
        return model.headline
    }

    private var notchSubtitle: String {
        speech.isListening ? "Tap the button to send" : model.detail
    }

    private func send() {
        let command = typed.trimmingCharacters(in: .whitespaces)
        guard !command.isEmpty else { return }
        typed = ""
        typing = false
        model.run(command)
    }
}

private struct SettingsSheet: View {
    @ObservedObject var model: PhoneModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("API keys") {
                    SecureField(model.hasTypeSafe ? "TypeSafe key saved — enter a replacement"
                                                  : "TypeSafe API key",
                                text: $model.pendingTypeSafe)
                    SecureField(model.hasOpenRouter ? "OpenRouter key saved — enter a replacement"
                                                    : "OpenRouter API key",
                                text: $model.pendingOpenRouter)
                    Button("Save keys") { model.saveKeys() }
                        .disabled(model.pendingTypeSafe.trimmingCharacters(in: .whitespaces).isEmpty &&
                                  model.pendingOpenRouter.trimmingCharacters(in: .whitespaces).isEmpty)
                    Text("Both are kept in this iPhone's Keychain. OpenRouter is the one the phone calls: your command and your shortcut names go to it, nothing else. TypeSafe is stored for the Mac app's pipeline and is not called from the phone.")
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
                    TextEditor(text: $model.shortcuts).frame(minHeight: 110)
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
