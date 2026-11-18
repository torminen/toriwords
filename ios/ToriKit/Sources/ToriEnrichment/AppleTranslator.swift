#if canImport(Translation)
import Foundation
import Observation
import Translation

/// Apple Translation EN→RU (doc 36 §6.3). Background fills use the UI-less session when the OS has it; otherwise they
/// go through `TranslationBridge`, which the app serves from a hidden `.translationTask` on its root view.
public struct AppleTranslator: MachineTranslator {
    public static let source = Locale.Language(identifier: "en")
    public static let target = Locale.Language(identifier: "ru")

    private let bridge: TranslationBridge

    public init(bridge: TranslationBridge) { self.bridge = bridge }

    /// `.installed` / `.supported` / `.unsupported`; shown in Settings → Translation.
    public static func availability() async -> LanguageAvailability.Status {
        await LanguageAvailability().status(from: source, to: target)
    }

    public func isReady() async -> Bool { await Self.availability() == .installed }

    public func translate(_ text: String) async throws -> String? {
        if #available(iOS 26, macOS 26, *) {
            let session = TranslationSession(installedSource: Self.source, target: Self.target)
            return try await session.translate(text).targetText
        }
        return try await bridge.translate(text)
    }
}

/// SwiftUI-free hook for the `.translationTask` fallback. The app attaches, on its root view while in the foreground:
/// `.translationTask(bridge.configuration) { session in await bridge.serve(session) }`
/// and calls `cancelAll()` when it leaves the foreground, so no request waits forever.
@MainActor @Observable
public final class TranslationBridge {
    public private(set) var configuration: TranslationSession.Configuration?
    private var queue: [(text: String, done: CheckedContinuation<String?, any Error>)] = []

    public init() {}

    func translate(_ text: String) async throws -> String? {
        try await withCheckedThrowingContinuation { done in
            queue.append((text, done))
            if configuration == nil {
                configuration = .init(source: AppleTranslator.source, target: AppleTranslator.target)
            } else {
                configuration?.invalidate()
            }
        }
    }

    /// Drains the queued requests with the session the modifier provides.
    public func serve(_ session: TranslationSession) async {
        while !queue.isEmpty {
            let request = queue.removeFirst()
            do { request.done.resume(returning: try await session.translate(request.text).targetText) }
            catch { request.done.resume(throwing: error) }
        }
    }

    public func cancelAll() {
        let pending = queue
        queue.removeAll()
        for request in pending { request.done.resume(throwing: CancellationError()) }
    }
}
#endif
