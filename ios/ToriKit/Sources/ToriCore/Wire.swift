/// A field value on the wire: string, number, boolean, null, or an array (`fsrs_w`).
public enum WireValue: Hashable, Sendable, Codable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([WireValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let i = try? c.decode(Int64.self) { self = .int(i) }
        else if let d = try? c.decode(Double.self) { self = .double(d) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else { self = .array(try c.decode([WireValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .int(let i): try c.encode(i)
        case .double(let d): try c.encode(d)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        }
    }
}

/// Wire form of a clock: the 32-char hex string.
extension HLCTimestamp: Codable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let s = try c.decode(String.self)
        guard let t = HLCTimestamp(s) else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "bad clock \(s)") }
        self = t
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(description)
    }
}

/// Wire form `{"v", "c", "u"}`.
extension FieldVersion: Codable where Value: Codable {
    enum CodingKeys: String, CodingKey { case v, c, u }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(value: try c.decode(Value.self, forKey: .v), clock: try c.decode(HLCTimestamp.self, forKey: .c),
                  rank: try c.decode(AuthorRank.self, forKey: .u))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(value, forKey: .v)
        try c.encode(clock, forKey: .c)
        try c.encode(rank, forKey: .u)
    }
}

/// Wire envelope.
extension Envelope: Codable where Value: Codable {
    enum CodingKeys: String, CodingKey { case id, type, schema, owner, deleted, mergedInto, fields }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(ToriID.self, forKey: .id), type: try c.decode(String.self, forKey: .type),
                  schema: try c.decode(Int.self, forKey: .schema), owner: try c.decodeIfPresent(ToriID.self, forKey: .owner),
                  deleted: try c.decodeIfPresent(Bool.self, forKey: .deleted) ?? false,
                  mergedInto: try c.decodeIfPresent(ToriID.self, forKey: .mergedInto),
                  fields: try c.decodeIfPresent([String: FieldVersion<Value>].self, forKey: .fields) ?? [:])
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(type, forKey: .type)
        try c.encode(schema, forKey: .schema)
        try c.encode(owner, forKey: .owner)  // explicit null
        try c.encode(deleted, forKey: .deleted)
        try c.encode(mergedInto, forKey: .mergedInto)
        try c.encode(fields, forKey: .fields)
    }
}

/// A synced record as pushed, pulled, exported and restored.
public typealias SyncRecord = Envelope<WireValue>
