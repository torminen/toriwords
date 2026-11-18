#if canImport(AVFoundation)
import AVFoundation

/// Pronunciation via `AVSpeechSynthesizer` (doc 36 §9). One instance owned by the app.
@MainActor
public final class SpeechPlayer: NSObject {
    public enum Trigger: Sendable {
        /// Tap on ▶ or long-press on a sentence: speaks even on silent, ducks other audio.
        case tap
        /// Auto-play on reveal: follows the silent switch, mixes with other audio.
        case autoPlay
    }

    public var accent: Accent
    private let synthesizer = AVSpeechSynthesizer()

    public init(accent: Accent) {
        self.accent = accent
        super.init()
        synthesizer.delegate = self
    }

    /// False → ▶ stays visible but disabled; tapping it explains how to add a voice.
    public var hasEnglishVoice: Bool { voice() != nil }

    public func speak(_ text: String, trigger: Trigger) {
        stop()
        guard let voice = voice() else { return }
        activateSession(trigger)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        synthesizer.speak(utterance)
    }

    /// Call when the card changes or the screen goes away.
    public func stop() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }

    private func voice() -> AVSpeechSynthesisVoice? {
        let all = AVSpeechSynthesisVoice.speechVoices()
        let candidates = all.map { v in
            VoicePicker.Voice(identifier: v.identifier, language: v.language, quality: {
                switch v.quality {
                case .premium: .premium
                case .enhanced: .enhanced
                default: .default
                }
            }())
        }
        guard let picked = VoicePicker.pick(accent, among: candidates) else { return nil }
        return AVSpeechSynthesisVoice(identifier: picked.identifier)
    }

    private func activateSession(_ trigger: Trigger) {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        switch trigger {
        case .tap: try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        case .autoPlay: try? session.setCategory(.ambient, mode: .spokenAudio)
        }
        try? session.setActive(true)
        #endif
    }

    fileprivate func deactivateSession() {
        #if os(iOS)
        guard !synthesizer.isSpeaking else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        #endif
    }
}

extension SpeechPlayer: AVSpeechSynthesizerDelegate {
    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.deactivateSession() }
    }

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.deactivateSession() }
    }
}
#endif
