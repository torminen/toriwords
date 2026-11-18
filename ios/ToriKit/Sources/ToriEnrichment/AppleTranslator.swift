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

    /// Below iOS 26 translations go through the bridge, which only the foreground UI serves: while the app is not
    /// active the translator reports "not ready", so pending entries are deferred instead of waiting or failing.
    public func isReady() async -> Bool {
        if #unavailable(iOS 26, macOS 26) {
            guard await bridge.isActive else { return false }
        }
        return await Self.availability() == .installed
    }

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
/// and keeps `isActive` in step with the scene phase. Requests made while inactive fail at once, a cancelled request
/// leaves the queue, and `cancelAll()` ends what is still queued when the app leaves the foreground: nothing waits
/// forever.
@MainActor @Observable
public final class TranslationBridge {
    public private(set) var configuration: TranslationSession.Configuration?
    /// True while the app is in the foreground (set by the app on scene-phase changes).
    public var isActive = false
    @ObservationIgnored private var queue: [(id: UInt64, text: String, done: CheckedContinuation<String?, any Error>)] = []
    @ObservationIgnored private var nextID: UInt64 = 0

    public init() {}

    func translate(_ text: String) async throws -> String? {
        guard isActive else { throw CancellationError() }
        nextID += 1
        let id = nextID
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { done in
                guard !Task.isCancelled else { return done.resume(throwing: CancellationError()) }
                queue.append((id, text, done))
                if configuration == nil {
                    configuration = .init(source: AppleTranslator.source, target: AppleTranslator.target)
                } else {
                    configuration?.invalidate()
                }
            }
        } onCancel: {
            Task { @MainActor in self.cancel(id) }
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

    private func cancel(_ id: UInt64) {
        guard let index = queue.firstIndex(where: { $0.id == id }) else { return }
        queue.remove(at: index).done.resume(throwing: CancellationError())
    }
}
#endif
