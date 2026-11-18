#if canImport(Translation)
import Testing
@testable import ToriEnrichment

/// The `.translationTask` fallback (iOS < 26) must never leave a request waiting: background refresh awaits it.
@MainActor
@Suite struct TranslationBridgeTests {
    @Test func inactiveBridgeFailsAtOnce() async {
        let bridge = TranslationBridge()
        await #expect(throws: CancellationError.self) { try await bridge.translate("hello") }
        #expect(bridge.configuration == nil)
    }

    @Test func cancelledRequestResumes() async {
        let bridge = TranslationBridge()
        bridge.isActive = true
        let request = Task { @MainActor in try await bridge.translate("hello") }
        while bridge.configuration == nil { await Task.yield() } // The request is queued.
        request.cancel()
        await #expect(throws: CancellationError.self) { try await request.value }
    }

    @Test func leavingTheForegroundEndsQueuedRequests() async {
        let bridge = TranslationBridge()
        bridge.isActive = true
        let request = Task { @MainActor in try await bridge.translate("hello") }
        while bridge.configuration == nil { await Task.yield() }
        bridge.isActive = false
        bridge.cancelAll()
        await #expect(throws: CancellationError.self) { try await request.value }
    }
}
#endif
