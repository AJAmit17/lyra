import AVFoundation
import Speech

/// Always-on listening for one phrase, on device only: nothing it hears is sent anywhere, no
/// transcript is kept, and every recognition task is thrown away when the next one starts.
/// It runs only while no command is being spoken or carried out.
@MainActor
final class WakeWord: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var status = ""
    var onHeard: (() -> Void)?
    /// Matched against the transcript with everything but letters and spaces removed.
    var phrase = "hey lyra"

    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var restart: Task<Void, Never>?
    private var tapInstalled = false
    private var generation = UUID()

    /// Apple only offers a phrase-sized recognition task; without on-device support the audio would
    /// go to Apple's servers continuously, which is not a trade worth making for a wake word.
    var isSupported: Bool { recognizer?.supportsOnDeviceRecognition == true }

    func start() {
        guard !isRunning, let recognizer, recognizer.isAvailable else { return }
        guard isSupported else { status = "On-device speech is unavailable, so the wake word stays off."; return }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
              SFSpeechRecognizer.authorizationStatus() == .authorized else { return }
        let current = UUID()
        generation = current
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.taskHint = .search
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else { return }
        input.installTap(onBus: 0, bufferSize: 2_048, format: format) { buffer, _ in request.append(buffer) }
        tapInstalled = true

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self, self.generation == current else { return }
                if let result, self.matches(result.bestTranscription.formattedString) {
                    self.stop()
                    self.onHeard?()
                    return
                }
                // A task ends after about a minute of audio, or on error. Start a fresh one.
                if error != nil || result?.isFinal == true { self.recycle() }
            }
        }
        do {
            engine.prepare()
            try engine.start()
            isRunning = true
            status = "Listening for “\(phrase)”."
        } catch {
            stop()
            status = error.localizedDescription
        }
    }

    func stop() {
        generation = UUID()
        restart?.cancel()
        restart = nil
        engine.stop()
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
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
        let cleaned = heard.lowercased().map { $0.isLetter || $0.isWhitespace ? $0 : " " }
        return String(cleaned).split(separator: " ").joined(separator: " ").contains(phrase)
    }
}
