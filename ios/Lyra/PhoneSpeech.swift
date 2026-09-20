import AVFoundation
import Speech

/// Microphone in, text out. Apple Speech, same as the Mac app.
@MainActor
final class PhoneSpeech: ObservableObject {
    @Published private(set) var transcript = ""
    @Published private(set) var isListening = false
    @Published private(set) var level: Double = 0
    @Published var status = ""
    var onFinal: ((String) -> Void)?

    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func requestPermissions() async -> Bool {
        if await AVAudioApplication.requestRecordPermission() == false {
            status = "Microphone access is off. Settings → Lyra → Microphone."
            return false
        }
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speech == .authorized else {
            status = "Speech Recognition access is off. Settings → Lyra → Speech Recognition."
            return false
        }
        return true
    }

    func start() async {
        guard !isListening else { return }
        guard await requestPermissions() else { return }
        guard let recognizer, recognizer.isAvailable else {
            status = "Speech recognition is unavailable right now."
            return
        }
        transcript = ""
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            status = error.localizedDescription
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
            var sum: Float = 0
            for frame in 0..<Int(buffer.frameLength) { sum += channel[frame] * channel[frame] }
            let rms = (sum / Float(buffer.frameLength)).squareRoot()
            let level = Double(max(0, min(1, (20 * log10(max(rms, 0.000_001)) + 55) / 55)))
            Task { @MainActor [weak self] in self?.level = level }
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result { transcript = result.bestTranscription.formattedString }
                if error != nil || result?.isFinal == true { finish(deliver: error == nil) }
            }
        }
        do {
            engine.prepare()
            try engine.start()
            isListening = true
            status = "Listening…"
        } catch {
            status = error.localizedDescription
            stopAudio()
        }
    }

    /// Ends the recording. The transcript so far is the command.
    func stop() {
        guard isListening else { return }
        finish(deliver: true)
    }

    private func finish(deliver: Bool) {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        stopAudio()
        guard deliver, !text.isEmpty else {
            if deliver { status = "Nothing was heard." }
            return
        }
        status = ""
        onFinal?(text)
    }

    private func stopAudio() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        request = nil
        task?.cancel()
        task = nil
        isListening = false
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
