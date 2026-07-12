import Foundation
import Speech
import AVFoundation
import Combine

// MARK: - Speech Recognition (Chat voice input)

/// Live speech-to-text for the chat composer's mic button.
/// Turkish locale first (UI language), falling back to the device default.
/// Counterpart of SpeechService (TTS) — this is the input direction.
@MainActor
final class SpeechRecognitionService: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var transcript = ""
    /// False after the user denies mic or speech permission; the composer
    /// hides the button instead of failing silently on every tap.
    @Published private(set) var isAvailable = true

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "tr-TR"))
        ?? SFSpeechRecognizer()
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func toggle() {
        if isRecording {
            stop()
        } else {
            Task { await start() }
        }
    }

    func start() async {
        guard !isRecording else { return }
        transcript = ""

        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else {
            isAvailable = false
            return
        }

        let micGranted = await AVAudioApplication.requestRecordPermission()
        guard micGranted else {
            isAvailable = false
            return
        }

        do {
            try begin()
        } catch {
            logWarning(
                "SpeechRecognition",
                "Sesli giriş başlatılamadı",
                details: error.localizedDescription
            )
            stop()
        }
    }

    private func begin() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        // The tap runs on the audio thread; appending buffers is thread-safe.
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true

        task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                if error != nil || result?.isFinal == true {
                    self.stop()
                }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isRecording = false
    }
}
