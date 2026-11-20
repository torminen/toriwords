#if canImport(AVFoundation)
import AVFoundation

/// Pronunciation via `AVSpeechSynthesizer`. One instance owned by the app.
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
    /// The picked voice per accent: listing the system voices takes tens of ms, and ▶ asks on every render and tap.
    /// Dropped when the installed voices change.
    private var cachedVoice: (accent: Accent, voice: AVSpeechSynthesisVoice?)?
    private var voicesObserver: (any NSObjectProtocol)?
    /// Audio session (de)activation blocks for a noticeable time (Xcode's "AVAudioSession Hang Risk"), so it runs on
    /// one serial queue off the main thread; serial keeps a deactivation from overtaking the next activation.
    private let sessionQueue = DispatchQueue(label: "SpeechPlayer.audioSession")
    /// Bumped by each `speak`: a speak whose session came up after a newer one was requested is dropped.
    private var generation = 0
    /// `generation` of the utterance handed to the synthesizer last.
    private var spokenGeneration = 0

    public init(accent: Accent) {
        self.accent = accent
        super.init()
        synthesizer.delegate = self
        voicesObserver = NotificationCenter.default.addObserver(
            forName: AVSpeechSynthesizer.availableVoicesDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.cachedVoice = nil }
        }
    }

    /// False → ▶ stays visible but disabled; tapping it explains how to add a voice.
    public var hasEnglishVoice: Bool { voice() != nil }

    /// Speaks once the audio session is active (a few ms later, off the main thread).
    public func speak(_ text: String, trigger: Trigger) {
        stop()
        guard hasEnglishVoice else { return }
        generation += 1
        let id = generation
        sessionQueue.async {
            Self.activateSession(trigger)
            Task { @MainActor [weak self] in
                guard let self, id == self.generation, let voice = self.voice() else { return }
                let utterance = AVSpeechUtterance(string: text)
                utterance.voice = voice
                self.spokenGeneration = id
                self.synthesizer.speak(utterance)
            }
        }
    }

    /// Call when the card changes or the screen goes away.
    public func stop() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }

    private func voice() -> AVSpeechSynthesisVoice? {
        if let cached = cachedVoice, cached.accent == accent { return cached.voice }
        let voice = pickVoice()
        cachedVoice = (accent, voice)
        return voice
    }

    private func pickVoice() -> AVSpeechSynthesisVoice? {
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
        // Among default-quality voices the identifier tie-break lands on Eloquence/novelty voices (Eddy, Albert…);
        // the system default for the language (Samantha for en-US, Daniel for en-GB) sounds far better.
        if picked.quality == .default, picked.language == accent.language,
           let system = AVSpeechSynthesisVoice(language: accent.language) {
            return system
        }
        return AVSpeechSynthesisVoice(identifier: picked.identifier)
    }

    nonisolated private static func activateSession(_ trigger: Trigger) {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        switch trigger {
        case .tap: try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        case .autoPlay: try? session.setCategory(.ambient, mode: .spokenAudio)
        }
        try? session.setActive(true)
        #endif
    }

    /// After an utterance ends; skipped while another is speaking or a newer `speak` is on its way.
    fileprivate func deactivateSession() {
        #if os(iOS)
        guard !synthesizer.isSpeaking, spokenGeneration == generation else { return }
        sessionQueue.async {
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
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
