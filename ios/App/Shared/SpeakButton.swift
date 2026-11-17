import SwiftUI
import ToriUI

/// ▶: tap speaks `text`; long-press speaks `sentence` (§9). Without an English voice it looks disabled and a tap
/// explains how to add one (PR2).
struct SpeakButton: View {
    let text: String
    var sentence: String?
    @Environment(AppEnvironment.self) private var env
    @State private var showNoVoice = false

    init(_ text: String, sentence: String? = nil) {
        self.text = text
        self.sentence = sentence
    }

    var body: some View {
        Image(systemName: "play.fill")
            .foregroundStyle(env.speech.hasEnglishVoice ? Palette.accent : Palette.textSecondary.opacity(0.5))
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .onTapGesture { play(text) }
            .onLongPressGesture { if let sentence { play(sentence) } }
            .accessibilityElement()
            .accessibilityLabel(Text("Play pronunciation"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { play(text) }
            .accessibilityActions {
                if let sentence { Button("Play sentence") { play(sentence) } }
            }
            .alert(Text("No English voice"), isPresented: $showNoVoice) {
                Button("OK") {}
            } message: {
                Text("To hear words, download an English voice in Settings → Accessibility → Spoken Content → Voices → English.")
            }
    }

    private func play(_ s: String) {
        if env.speech.hasEnglishVoice { env.speak(s, .tap) } else { showNoVoice = true }
    }
}
