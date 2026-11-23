import Foundation
import Testing
import ToriShared

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() { lock.withLock { value += 1 } }
    var count: Int { lock.withLock { value } }
}

@Test func onMainRunsInlineWithoutHop() {
    let counter = Counter()
    var hopped = false
    MainThreadHandoff.run(isMainThread: true, hop: { _ in hopped = true }) { counter.increment() }
    #expect(counter.count == 1)
    #expect(!hopped)
}

@Test func offMainDefersToHopAndRunsOnce() {
    let counter = Counter()
    var captured: [@Sendable () -> Void] = []
    MainThreadHandoff.run(isMainThread: false, hop: { captured.append($0) }) { counter.increment() }
    #expect(counter.count == 0)
    #expect(captured.count == 1)
    captured.first?()
    #expect(counter.count == 1)
}
