import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// A record ID: 16 bytes, ordered as unsigned bytes (doc 36 §4.1, §11.2). Text form is lowercase hyphenated.
public struct ToriID: Hashable, Comparable, Sendable, CustomStringConvertible {
    /// Bytes 0–7 and 8–15, big-endian, so integer order equals unsigned byte order.
    public let high: UInt64
    public let low: UInt64

    public init(high: UInt64, low: UInt64) {
        self.high = high
        self.low = low
    }

    public init(bytes: some Collection<UInt8>) {
        precondition(bytes.count == 16, "ToriID needs 16 bytes")
        var h: UInt64 = 0, l: UInt64 = 0
        for (i, b) in bytes.enumerated() {
            if i < 8 { h = h << 8 | UInt64(b) } else { l = l << 8 | UInt64(b) }
        }
        self.init(high: h, low: l)
    }

    /// Parses `8-4-4-4-12` hex, either case; nil otherwise.
    public init?(_ text: String) {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.map(\.utf8.count) == [8, 4, 4, 4, 12] else { return nil }
        let hex = parts.joined()
        guard hex.utf8.allSatisfy(\.isHexDigitASCII),
              let h = UInt64(hex.prefix(16), radix: 16), let l = UInt64(hex.suffix(16), radix: 16) else { return nil }
        self.init(high: h, low: l)
    }

    public var bytes: [UInt8] {
        (0..<8).map { UInt8(truncatingIfNeeded: high >> (56 - 8 * $0)) }
            + (0..<8).map { UInt8(truncatingIfNeeded: low >> (56 - 8 * $0)) }
    }

    public var description: String {
        let hex = String(high, radix: 16).leftPadded(16) + String(low, radix: 16).leftPadded(16)
        let c = Array(hex)
        return [c[0..<8], c[8..<12], c[12..<16], c[16..<20], c[20..<32]].map { String($0) }.joined(separator: "-")
    }

    public static func < (a: ToriID, b: ToriID) -> Bool { (a.high, a.low) < (b.high, b.low) }

    // MARK: UUIDv7

    /// UUIDv7 (RFC 9562): 48-bit Unix ms ‖ ver 7 ‖ 12-bit `randA` ‖ variant 0b10 ‖ 62-bit `randB` (extra bits are masked off).
    public static func v7(unixMs: Int64, randA: UInt16, randB: UInt64) -> ToriID {
        precondition(unixMs >= 0 && unixMs < 1 << 48)
        let h = UInt64(unixMs) << 16 | 0x7000 | UInt64(randA & 0x0FFF)
        return ToriID(high: h, low: 0x8000_0000_0000_0000 | (randB & 0x3FFF_FFFF_FFFF_FFFF))
    }

    /// A new random UUIDv7; time and randomness are injected.
    public static func v7(unixMs: Int64, using rng: inout some RandomNumberGenerator) -> ToriID {
        v7(unixMs: unixMs, randA: UInt16.random(in: 0...0x0FFF, using: &rng), randB: rng.next())
    }

    // MARK: UUIDv5

    /// The Toriwords namespace (fixed forever).
    public static let namespace = ToriID("6f1c2a4e-3b7d-5e59-9a0c-5d8e7f2b1c34")!

    /// UUIDv5 (SHA-1) of a UTF-8 name under the Toriwords namespace.
    public static func v5(_ name: String) -> ToriID {
        var data = Data(namespace.bytes)
        data.append(contentsOf: Array(name.utf8))
        var b = Array(Insecure.SHA1.hash(data: data).prefix(16))
        b[6] = b[6] & 0x0F | 0x50
        b[8] = b[8] & 0x3F | 0x80
        return ToriID(bytes: b)
    }

    // MARK: Deterministic IDs (doc 36 §11.2)

    public static func languagePair(native: String, target: String) -> ToriID { v5("pair:\(native):\(target)") }
    public static let settings = v5("settings")
    public static func card(entry: ToriID, direction: CardDirection) -> ToriID { v5("card:\(entry):\(direction.rawValue)") }
    public static func source(urlKey: String) -> ToriID { v5("source:\(urlKey)") }
    public static func entryTag(entry: ToriID, tag: ToriID) -> ToriID { v5("entrytag:\(entry):\(tag)") }
    public static func autoSense(entry: ToriID, ordinal: Int) -> ToriID { v5("autosense:\(entry):\(ordinal)") }
}

/// Card direction; the raw value is the synced name. Declaration order is the queue order (§7.7).
public enum CardDirection: String, CaseIterable, Comparable, Sendable {
    case recognition, recall, cloze

    public static func < (a: Self, b: Self) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }
}

extension UInt8 {
    var isHexDigitASCII: Bool { (0x30...0x39).contains(self) || (0x41...0x46).contains(self) || (0x61...0x66).contains(self) }
}

extension String {
    func leftPadded(_ width: Int) -> String { String(repeating: "0", count: max(0, width - count)) + self }
}
