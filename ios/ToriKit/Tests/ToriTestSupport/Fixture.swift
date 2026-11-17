import Foundation
import Testing

/// A JSON value from a fixture file (Sendable, so cases can be `@Test(arguments:)`).
public enum JSON: Sendable, Equatable, Decodable {
    case null, bool(Bool), int(Int64), double(Double), string(String), array([JSON]), object([String: JSON])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let i = try? c.decode(Int64.self) { self = .int(i) }
        else if let d = try? c.decode(Double.self) { self = .double(d) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSON].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSON].self)) }
    }

    public subscript(key: String) -> JSON {
        if case .object(let o) = self, let v = o[key] { return v }
        return .null
    }

    public subscript(index: Int) -> JSON {
        if case .array(let a) = self { return a[index] }
        return .null
    }

    public var isNull: Bool { self == .null }
    public var string: String? { if case .string(let s) = self { s } else { nil } }
    public var int: Int? { if case .int(let i) = self { Int(i) } else { nil } }
    public var int64: Int64? { if case .int(let i) = self { i } else { nil } }
    public var double: Double? {
        switch self {
        case .double(let d): d
        case .int(let i): Double(i)
        default: nil
        }
    }
    public var bool: Bool? { if case .bool(let b) = self { b } else { nil } }
    public var array: [JSON] { if case .array(let a) = self { a } else { [] } }
    public var object: [String: JSON] { if case .object(let o) = self { o } else { [:] } }
    public func has(_ key: String) -> Bool { object[key] != nil }
}

/// One fixture case; the test name shows the case id.
public struct FixtureCase: Sendable, CustomTestStringConvertible {
    public let id: String
    public let json: JSON
    /// The file's top-level object (kind, source, params…).
    public let file: JSON

    public var testDescription: String { id }
    public subscript(key: String) -> JSON { json[key] }
}

public enum Fixture {
    public static func file(_ relativePath: String) -> JSON {
        do {
            return try JSONDecoder().decode(JSON.self, from: Data(contentsOf: FixtureLocator.url(relativePath)))
        } catch {
            fatalError("cannot load fixture \(relativePath): \(error)")
        }
    }

    public static func cases(_ relativePath: String) -> [FixtureCase] {
        let f = file(relativePath)
        return f["cases"].array.map { FixtureCase(id: $0["id"].string!, json: $0, file: f) }
    }
}

/// Strict string equality: same code points (Swift `==` uses canonical equivalence).
public func sameScalars(_ a: String?, _ b: String?) -> Bool {
    a.map { Array($0.unicodeScalars) } == b.map { Array($0.unicodeScalars) }
}
