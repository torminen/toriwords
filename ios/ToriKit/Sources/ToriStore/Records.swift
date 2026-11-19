import Foundation
import GRDB
import ToriCore

extension ToriID: DatabaseValueConvertible {
    public var databaseValue: DatabaseValue { Data(bytes).databaseValue }

    public static func fromDatabaseValue(_ dbValue: DatabaseValue) -> ToriID? {
        guard let data = Data.fromDatabaseValue(dbValue), data.count == 16 else { return nil }
        return ToriID(bytes: data)
    }
}

/// How a synced column maps to the wire.
enum FieldKind {
    case text, int, real, bool, id, json

    func toWire(_ v: DatabaseValue) -> WireValue {
        if v.isNull { return .null }
        switch self {
        case .text: return String.fromDatabaseValue(v).map(WireValue.string) ?? .null
        case .int: return Int64.fromDatabaseValue(v).map(WireValue.int) ?? .null
        case .real: return Double.fromDatabaseValue(v).map(WireValue.double) ?? .null
        case .bool: return .bool((Int64.fromDatabaseValue(v) ?? 0) != 0)
        case .id: return ToriID.fromDatabaseValue(v).map { .string($0.description) } ?? .null
        case .json:
            guard let s = String.fromDatabaseValue(v), let w = try? JSONDecoder().decode(WireValue.self, from: Data(s.utf8))
            else { return .null }
            return w
        }
    }

    /// Lenient: a value of the wrong JSON type is stored as NULL rather than failing the page.
    func toDatabase(_ w: WireValue) -> DatabaseValue {
        switch (self, w) {
        case (_, .null): return .null
        case (.text, .string(let s)): return s.databaseValue
        case (.int, .int(let i)): return i.databaseValue
        case (.int, .double(let d)) where d.rounded() == d: return Int64(d).databaseValue
        case (.real, .double(let d)): return d.databaseValue
        case (.real, .int(let i)): return Double(i).databaseValue
        case (.bool, .bool(let b)): return (b ? 1 : 0).databaseValue
        case (.bool, .int(let i)): return (i != 0 ? 1 : 0).databaseValue
        case (.id, .string(let s)): return ToriID(s)?.databaseValue ?? .null
        case (.json, _): return String(decoding: try! JSONEncoder().encode(w), as: UTF8.self).databaseValue
        default: return .null
        }
    }
}

/// One synced record type: its table (= wire `type`), synced fields and owner column.
struct RecordType: Hashable, Sendable {
    let name: String
    let fields: [String: FieldKind]
    /// Column that is the envelope `owner` (kept on tombstones).
    let ownerColumn: String?
    /// Types whose duplicates merge and that carry a `canonical_id`.
    var mergeable: Bool { ["entry", "sense", "context", "tag", "source"].contains(name) }

    static func == (a: Self, b: Self) -> Bool { a.name == b.name }
    func hash(into h: inout Hasher) { h.combine(name) }

    static let languagePair = RecordType(name: "language_pair", fields: [
        "native_lang": .text, "target_lang": .text, "created_at": .int], ownerColumn: nil)
    static let entry = RecordType(name: "entry", fields: [
        "language_pair_id": .id, "text": .text, "ipa": .text, "note": .text, "status": .text, "excluded_reason": .text,
        "enrichment_status": .text, "needs_check": .bool, "origin": .text, "created_at": .int, "updated_at": .int],
        ownerColumn: nil)
    static let sense = RecordType(name: "sense", fields: [
        "entry_id": .id, "translation": .text, "definition": .text, "part_of_speech": .text, "position": .real,
        "translation_src": .text, "definition_src": .text, "pos_src": .text, "dict_version": .text,
        "dict_headword_key": .text, "dict_sense_ordinal": .int], ownerColumn: "entry_id")
    static let source = RecordType(name: "source", fields: [
        "kind": .text, "url": .text, "title": .text, "app": .text], ownerColumn: nil)
    static let context = RecordType(name: "context", fields: [
        "entry_id": .id, "sense_id": .id, "sentence": .text, "highlight_offset": .int, "highlight_length": .int,
        "source_id": .id, "captured_at": .int], ownerColumn: "entry_id")
    static let card = RecordType(name: "card", fields: [
        "entry_id": .id, "direction": .text, "import_ref": .text, "created_at": .int], ownerColumn: "entry_id")
    static let reviewLog = RecordType(name: "review_log", fields: [
        "card_id": .id, "owner_entry_id": .id, "reviewed_at": .int, "utc_offset_min": .int, "rating": .int,
        "answer_ms": .int, "device_id": .id, "original_rating": .int, "import_ref": .text], ownerColumn: "owner_entry_id")
    static let tag = RecordType(name: "tag", fields: ["name": .text], ownerColumn: nil)
    static let entryTag = RecordType(name: "entry_tag", fields: [
        "entry_id": .id, "tag_id": .id, "present": .bool], ownerColumn: "entry_id")
    static let settings = RecordType(name: "settings", fields: [
        "new_words_per_day": .int, "desired_retention": .real, "fsrs_w": .json, "params_id": .text,
        "scheduler_version": .int], ownerColumn: nil)
    static let device = RecordType(name: "device", fields: [
        "platform": .text, "display_name": .text, "first_seen": .int], ownerColumn: nil)

    /// Parents before children (export order and `markAllPending` order).
    static let all: [RecordType] = [languagePair, settings, device, entry, source, tag, sense, context, card, entryTag, reviewLog]
    static let byName = Dictionary(uniqueKeysWithValues: all.map { ($0.name, $0) })

    var fieldNames: [String] { fields.keys.sorted() }
}

/// `field_clocks` entry `{"c", "u"}`.
struct FieldClock: Codable, Hashable {
    var c: String
    var u: Int
}

enum JSONText {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }()

    static func encode(_ v: some Encodable) -> String { String(decoding: try! encoder.encode(v), as: UTF8.self) }

    static func decode<T: Decodable>(_ t: T.Type, _ s: String?) -> T? {
        s.flatMap { try? JSONDecoder().decode(t, from: Data($0.utf8)) }
    }
}

/// Envelope <-> row.
enum RecordIO {
    /// The local record as an envelope (all fields with clocks plus `extra`); nil if absent.
    static func load(_ db: Database, _ type: RecordType, _ id: ToriID) throws -> SyncRecord? {
        guard let row = try Row.fetchOne(db, sql: "SELECT * FROM \(type.name) WHERE id = ?", arguments: [id]) else { return nil }
        return envelope(type, row)
    }

    static func envelope(_ type: RecordType, _ row: Row) -> SyncRecord {
        let clocks = JSONText.decode([String: FieldClock].self, row["field_clocks"]) ?? [:]
        var fields = JSONText.decode([String: FieldVersion<WireValue>].self, row["extra"]) ?? [:]
        for (name, clock) in clocks {
            guard let kind = type.fields[name], let c = HLCTimestamp(clock.c) else { continue }
            fields[name] = FieldVersion(value: kind.toWire(row[name] as DatabaseValue), clock: c,
                                        rank: AuthorRank(rawValue: clock.u) ?? .automatic)
        }
        let owner: ToriID? = type.ownerColumn.flatMap { row[$0] }
        return SyncRecord(id: row["id"], type: type.name, schema: row["schema"], owner: owner,
                          deleted: (row["deleted"] as Int) != 0, mergedInto: row["merged_into"], fields: fields)
    }

    /// Writes the whole synced state of `record` (local columns untouched), then its row-local derived columns.
    static func store(_ db: Database, _ type: RecordType, _ record: SyncRecord) throws {
        try db.execute(sql: "INSERT OR IGNORE INTO \(type.name) (id) VALUES (?)", arguments: [record.id])
        var clocks: [String: FieldClock] = [:]
        var extra: [String: FieldVersion<WireValue>] = [:]
        for (name, f) in record.fields {
            if type.fields[name] != nil {
                clocks[name] = FieldClock(c: f.clock.description, u: f.rank.rawValue)
            } else {
                extra[name] = f
            }
        }
        var columns = ["field_clocks", "deleted", "merged_into", "extra", "schema"]
        var values: [DatabaseValueConvertible?] = [JSONText.encode(clocks), record.deleted ? 1 : 0, record.mergedInto,
                                                   extra.isEmpty ? nil : JSONText.encode(extra), record.schema]
        for name in type.fieldNames {
            columns.append(name)
            if name == type.ownerColumn, record.fields[name] == nil {
                values.append(record.owner)
            } else {
                values.append(record.fields[name].map { type.fields[name]!.toDatabase($0.value) } ?? DatabaseValue.null)
            }
        }
        let set = columns.map { "\($0) = ?" }.joined(separator: ", ")
        try db.execute(sql: "UPDATE \(type.name) SET \(set) WHERE id = ?", arguments: StatementArguments(values + [record.id] as [(any DatabaseValueConvertible)?]))
        try Derived.rowLocal(db, type, record.id)
    }
}

/// Derived local columns computed from the row itself: keys, folds, review day.
enum Derived {
    static func rowLocal(_ db: Database, _ type: RecordType, _ id: ToriID) throws {
        func update(_ sql: String, _ args: [DatabaseValueConvertible?]) throws {
            try db.execute(sql: sql, arguments: StatementArguments(args + [id] as [(any DatabaseValueConvertible)?]))
        }
        func text(_ col: String) throws -> String? {
            try String.fetchOne(db, sql: "SELECT \(col) FROM \(type.name) WHERE id = ?", arguments: [id])
        }
        switch type.name {
        case "entry":
            let t = try text("text")
            try update("UPDATE entry SET match_key = ?, text_fold = ? WHERE id = ?", [t.map(TextKey.matchKey), t.map(TextKey.searchFold)])
        case "sense":
            let tr = try text("translation"), def = try text("definition")
            try update("UPDATE sense SET translation_fold = ?, definition_fold = ? WHERE id = ?",
                       [tr.map(TextKey.searchFold), def.map(TextKey.searchFold)])
        case "context":
            try update("UPDATE context SET sentence_fold = ? WHERE id = ?", [try text("sentence").map(TextKey.searchFold)])
        case "source":
            try update("UPDATE source SET url_key = ? WHERE id = ?", [try text("url").map(TextKey.urlKey)])
        case "tag":
            try update("UPDATE tag SET name_key = ? WHERE id = ?", [try text("name").map(TextKey.tagKey)])
        case "review_log":
            let row = try Row.fetchOne(db, sql: "SELECT reviewed_at, utc_offset_min FROM review_log WHERE id = ?", arguments: [id])
            let day: Int? = {
                guard let at: Int64 = row?["reviewed_at"], let off: Int = row?["utc_offset_min"] else { return nil }
                return DayModel.dayNumber(unixMs: at, utcOffsetMin: off)
            }()
            try update("UPDATE review_log SET review_day = ? WHERE id = ?", [day])
        default: break
        }
    }
}
