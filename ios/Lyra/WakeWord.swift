import AVFoundation
import Speech

/// Listens for one phrase, on device only, while the app is in front.
///
/// iOS will not let an app hold the microphone open in the background, so this is not a
/// system-wide "hey Lyra" the way the Mac's is — nothing here runs once you leave the app.
/// Siri is the only always-on listener on iOS; "Hey Siri, ask Lyra" reaches the same command path
/// through the app's App Intent.
@MainActor
final class WakeWord: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var status = ""
    var onHeard: (() -> Void)?
    var phrase = "hey lyra"

    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var restart: Task<Void, Never>?
    private var generation = UUID()

    var isSupported: Bool { recognizer?.supportsOnDeviceRecognition == true }

    func start() {
        guard !isRunning, isSupported, let recognizer, recognizer.isAvailable else { return }
        guard AVAudioApplication.shared.recordPermission == .granted,
              SFSpeechRecognizer.authorizationStatus() == .authorized else { return }
        let current = UUID()
        generation = current

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true)
        } catch {
            status = error.localizedDescription
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.taskHint = .search
        self.request = request

        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 2_048, format: input.outputFormat(forBus: 0)) { buffer, _ in
            request.append(buffer)
        }
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self, generation == current else { return }
                if let result, matches(result.bestTranscription.formattedString) {
                    stop()
                    onHeard?()
                    return
                }
                // A recognition task ends after about a minute of audio, or on error.
                if error != nil || result?.isFinal == true { recycle() }
            }
        }
        do {
            engine.prepare()
            try engine.start()
            isRunning = true
            status = "Listening for “\(phrase)”."
        } catch {
            status = error.localizedDescription
            stop()
        }
    }

    func stop() {
        generation = UUID()
        restart?.cancel()
        restart = nil
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        request = nil
        task?.cancel()
        task = nil
        isRunning = false
    }

    private func recycle() {
        stop()
        restart = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            start()
        }
    }

    private func matches(_ heard: String) -> Bool {
        let letters = heard.lowercased().map { $0.isLetter || $0.isWhitespace ? $0 : " " }
        return String(letters).split(separator: " ").joined(separator: " ").contains(phrase)
    }
}
