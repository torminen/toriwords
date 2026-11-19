/// Hybrid logical clock, with the clock-ahead reset against the last server time.
public struct HLCTimestamp: Hashable, Comparable, Sendable, CustomStringConvertible {
    public var ms: Int64
    public var counter: UInt16
    /// First 64 bits of the Device ID.
    public var node: UInt64

    public init(ms: Int64, counter: UInt16, node: UInt64) {
        self.ms = ms
        self.counter = counter
        self.node = node
    }

    /// Parses the 32-char lowercase hex form; nil otherwise.
    public init?(_ text: String) {
        let u = Array(text.utf8)
        guard u.count == 32, u.allSatisfy({ (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }),
              let ms = Int64(String(text.prefix(12)), radix: 16),
              let counter = UInt16(String(text.dropFirst(12).prefix(4)), radix: 16),
              let node = UInt64(String(text.suffix(16)), radix: 16) else { return nil }
        self.init(ms: ms, counter: counter, node: node)
    }

    /// `ms` (12 hex) ‖ `counter` (4 hex) ‖ `node` (16 hex); string order = clock order.
    public var description: String {
        String(ms, radix: 16).leftPadded(12) + String(counter, radix: 16).leftPadded(4) + String(node, radix: 16).leftPadded(16)
    }

    public static func < (a: Self, b: Self) -> Bool { (a.ms, a.counter, a.node) < (b.ms, b.counter, b.node) }
}

/// Persisted HLC state `{ms, counter}`.
public struct HLCState: Hashable, Codable, Sendable {
    public static let dayMs: Int64 = 86_400_000
    public static let hourMs: Int64 = 3_600_000

    public var ms: Int64
    public var counter: Int

    public init(ms: Int64 = 0, counter: Int = 0) {
        self.ms = ms
        self.counter = counter
    }

    /// Local write: returns the clock for the written field.
    public mutating func localWrite(now: Int64, node: UInt64) -> HLCTimestamp {
        if now > ms { (ms, counter) = (now, 0) } else { bump(counter + 1) }
        return HLCTimestamp(ms: ms, counter: UInt16(counter), node: node)
    }

    /// Receive a pulled clock. A remote clock more than 24 h ahead of `now` is not adopted.
    public mutating func receive(_ remote: HLCTimestamp, now: Int64) {
        if remote.ms - now > Self.dayMs { return }
        let newMs = max(ms, remote.ms, now)
        let r = Int(remote.counter)
        let c = switch (newMs == ms, newMs == remote.ms) {
        case (true, true): max(counter, r) + 1
        case (true, false): counter + 1
        case (false, true): r + 1
        case (false, false): 0
        }
        ms = newMs
        bump(c)
    }

    /// Clock-ahead recovery before push: if the clock is more than 1 h ahead of the last server time,
    /// reset it and re-stamp the pending fields in outbox order. Returns the new clocks, or nil when no reset is needed.
    public mutating func recoverIfAhead(lastServerTime: Int64, now: Int64, node: UInt64, pendingFields: Int) -> [HLCTimestamp]? {
        guard ms - lastServerTime > Self.hourMs else { return nil }
        (ms, counter) = (max(lastServerTime, now), 0)
        return (0..<pendingFields).map { _ in localWrite(now: now, node: node) }
    }

    /// Server rule: a pushed clock more than 1 h ahead of server time is rejected with `clock_skew`.
    public static func serverAccepts(_ clock: HLCTimestamp, serverTime: Int64) -> Bool {
        clock.ms - serverTime <= hourMs
    }

    private mutating func bump(_ c: Int) {
        if c > Int(UInt16.max) { (ms, counter) = (ms + 1, 0) } else { counter = c }
    }
}
