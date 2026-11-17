/// Author rank of a field write: 1 for a direct user action, 0 for anything automatic (doc 36 §11.3).
public enum AuthorRank: Int, Comparable, Codable, Sendable {
    case automatic = 0, user = 1
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

/// A synced field value with its clock `c` and rank `u`.
public struct FieldVersion<Value: Sendable & Equatable>: Equatable, Sendable {
    public var value: Value
    public var clock: HLCTimestamp
    public var rank: AuthorRank

    public init(value: Value, clock: HLCTimestamp, rank: AuthorRank) {
        self.value = value
        self.clock = clock
        self.rank = rank
    }

    /// `(u, c)` order: rank first, then clock.
    public func wins(over other: Self) -> Bool { (rank, clock) > (other.rank, other.clock) }

    /// The only conflict rule: remote wins only if it beats local.
    public static func merge(local: Self, remote: Self) -> Self { remote.wins(over: local) ? remote : local }
}

/// A synced record (doc 36 §11.1). `fields` holds only the fields present (a partial push carries a subset).
public struct Envelope<Value: Sendable & Equatable>: Equatable, Sendable {
    public var id: ToriID
    public var type: String
    public var schema: Int
    public var owner: ToriID?
    public var deleted: Bool
    public var mergedInto: ToriID?
    public var fields: [String: FieldVersion<Value>]

    public init(id: ToriID, type: String, schema: Int, owner: ToriID?, deleted: Bool, mergedInto: ToriID?,
                fields: [String: FieldVersion<Value>]) {
        self.id = id
        self.type = type
        self.schema = schema
        self.owner = owner
        self.deleted = deleted
        self.mergedInto = mergedInto
        self.fields = fields
    }

    /// Envelope merge: deleted = OR; mergedInto non-null beats null, smaller ID wins; fields per field
    /// (unknown kept, disjoint unioned); a tombstone drops all field values; schema = max. Commutative.
    public static func merge(local: Self, remote: Self) -> Self {
        let deleted = local.deleted || remote.deleted
        let into = [local.mergedInto, remote.mergedInto].compactMap { $0 }.min()
        let fields = deleted ? [:] : local.fields.merging(remote.fields) { FieldVersion.merge(local: $0, remote: $1) }
        return Envelope(id: local.id, type: local.type, schema: max(local.schema, remote.schema), owner: local.owner,
                        deleted: deleted, mergedInto: into, fields: fields)
    }
}
