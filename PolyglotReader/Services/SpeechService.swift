import Foundation
import Combine
import AVFoundation
import NaturalLanguage

/// Sesli okuma (Text-to-Speech) servisi.
///
/// `AVSpeechSynthesizer`'ı sarmalar ve okuma durumunu (`@Published`) UI'a yayınlar.
/// Delegate geri çağrıları AVFoundation tarafından ana iş parçacığında teslim edildiğinden
/// `@Published` mutasyonları güvenle ana iş parçacığında gerçekleşir.
///
/// Reader, sayfa metnini `speak(_:)` ile verir; bir sayfa bitince `onFinish` tetiklenir
/// ve reader otomatik olarak bir sonraki sayfaya geçip okumaya devam edebilir.
final class SpeechService: NSObject, ObservableObject {
    /// O an aktif olarak konuşma sürüyor mu (duraklatılmış olsa bile true).
    @Published private(set) var isSpeaking = false
    /// Konuşma duraklatıldı mı.
    @Published private(set) var isPaused = false

    /// Okuma hızı. AVFoundation aralığı (min...max) içinde tutulur.
    @Published var rate: Float = AVSpeechUtteranceDefaultSpeechRate {
        didSet { rate = min(max(rate, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate) }
    }

    /// Bir metin bloğu (sayfa) tamamlandığında çağrılır. Reader bunu bir sonraki
    /// sayfaya geçmek için kullanır.
    var onFinish: (() -> Void)?

    private let synthesizer = AVSpeechSynthesizer()

    /// Kullanıcı bilerek durdurdu bayrağı. `stopSpeaking` çağrısı bazı iOS
    /// sürümlerinde `didCancel` yerine `didFinish` teslim eder; bu durumda
    /// `onFinish` tetiklenir ve otomatik sayfa ilerletme okumayı YENİDEN
    /// başlatır ("durdur çalışmıyor" bug'ı). Bayrak bu yolu kesin kapatır.
    private var wasStoppedByUser = false

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Control

    /// Verilen metni okumaya başlar. Önceki okuma varsa iptal edilir.
    func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            onFinish?()
            return
        }

        configureAudioSession()

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.rate = rate
        if let voice = preferredVoice(for: trimmed) {
            utterance.voice = voice
        }

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        wasStoppedByUser = false
        isPaused = false
        synthesizer.speak(utterance)
    }

    func pause() {
        guard synthesizer.isSpeaking, !isPaused else { return }
        synthesizer.pauseSpeaking(at: .word)
        isPaused = true
    }

    func resume() {
        guard isPaused else { return }
        synthesizer.continueSpeaking()
        isPaused = false
    }

    /// Tamamen durdurur. `onFinish` tetiklenmez (kullanıcı bilerek durdurdu).
    func stop() {
        wasStoppedByUser = true
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        isPaused = false
        deactivateAudioSession()
    }

    // MARK: - Helpers

    /// Metnin dilini tespit edip uygun sesi seçer; bulunamazsa sistem varsayılanına düşer.
    private func preferredVoice(for text: String) -> AVSpeechSynthesisVoice? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage?.rawValue else { return nil }

        // Tam eşleşen sesi dene (örn. "tr-TR"); yoksa dil kodu prefiksiyle eşle (örn. "tr").
        if let exact = AVSpeechSynthesisVoice(language: language) {
            return exact
        }
        let prefix = language.split(separator: "-").first.map(String.init) ?? language
        return AVSpeechSynthesisVoice.speechVoices().first { $0.language.hasPrefix(prefix) }
    }

    /// Okuma bitince ses oturumunu bırak — başka uygulamaların sesi (müzik,
    /// podcast) kaldığı yerden devam edebilsin.
    private func deactivateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            logWarning("SpeechService", "Audio session kapatılamadı", details: error.localizedDescription)
        }
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: [])
            try session.setActive(true, options: [])
        } catch {
            logWarning("SpeechService", "Audio session yapılandırılamadı", details: error.localizedDescription)
        }
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension SpeechService: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        isSpeaking = true
        isPaused = false
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isSpeaking = false
        isPaused = false
        // Kullanıcı durdurduysa otomatik ilerletmeyi tetikleme — stopSpeaking
        // bazı durumlarda didCancel yerine buraya düşer.
        guard !wasStoppedByUser else { return }
        onFinish?()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        isSpeaking = false
        isPaused = false
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        isPaused = true
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        isPaused = false
    }
}
