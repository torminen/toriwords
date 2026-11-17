import Foundation
import GRDB
import ToriCore

/// JSON backup wrapper (§14.2).
public struct Backup: Codable, Sendable {
    public static let formatName = "toriwords-backup"
    public static let supportedVersion = 1
    public static let supportedProtocol = 1

    public var format: String
    public var version: Int
    public var exportedAt: String
    public var `protocol`: Int
    public var attribution: String
    public var records: [SyncRecord]
}

public struct RestoreSummary: Equatable, Sendable {
    /// Entries new to this device that stayed separate words.
    public var imported = 0
    /// Entries new to this device that merged with an existing word.
    public var merged = 0
    /// Entries deleted earlier on this device (tombstoned), not restored.
    public var deletedEarlier = 0
}

extension ToriStore {
    /// All non-deleted records with their field clocks, parents first. Children of deleted Entries are left out.
    public func exportBackup(attribution: String) throws -> Data {
        let records: [SyncRecord] = try db.read { db in
            try RecordType.all.flatMap { type in
                let ownerFilter = type.ownerColumn.map { col in
                    " AND NOT EXISTS (SELECT 1 FROM entry o WHERE o.id = \(type.name).\(col) AND o.deleted = 1)"
                } ?? ""
                return try Row.fetchAll(db, sql: "SELECT * FROM \(type.name) WHERE deleted = 0\(ownerFilter) ORDER BY id")
                    .map { RecordIO.envelope(type, $0) }
            }
        }
        let formatter = ISO8601DateFormatter()
        let backup = Backup(format: Backup.formatName, version: Backup.supportedVersion,
                            exportedAt: formatter.string(from: Date(timeIntervalSince1970: Double(clock()) / 1000)),
                            protocol: Backup.supportedProtocol, attribution: attribution, records: records)
        return try JSONText.encoder.encode(backup)
    }

    /// Restore (§14.2): validates the wrapper, then applies the records as if pulled, in pages; idempotent.
    /// Locally changed records are added to the outbox while signed in. (The pre-restore sync cycle is ToriSync's.)
    public func restore(_ data: Data, pageSize: Int = 1000) throws -> RestoreSummary {
        struct Header: Decodable { var format: String?; var version: Int?; var `protocol`: Int? }
        guard let header = try? JSONDecoder().decode(Header.self, from: data), header.format == Backup.formatName,
              let version = header.version, let proto = header.protocol else { throw StoreError.notABackup }
        guard version <= Backup.supportedVersion, proto <= Backup.supportedProtocol else { throw StoreError.updateRequired }
        guard let backup = try? JSONDecoder().decode(Backup.self, from: data) else { throw StoreError.notABackup }

        let entryIDs = backup.records.filter { $0.type == "entry" }.map(\.id)
        let before: [ToriID: Bool] = try db.read { db in
            var known: [ToriID: Bool] = [:]
            for id in entryIDs {
                if let deleted = try Bool.fetchOne(db, sql: "SELECT deleted FROM entry WHERE id = ?", arguments: [id]) { known[id] = deleted }
            }
            return known
        }
        var start = 0
        while start < backup.records.count {
            let page = backup.records[start..<min(start + pageSize, backup.records.count)]
            try write { tx in
                for record in page {
                    guard let type = RecordType.byName[record.type] else { continue }
                    let outcome = try Apply.record(tx, type, record)
                    if outcome == .inserted || outcome == .updated { try tx.outbox(type, record.id, "*", tx.stamp()) }
                }
            }
            start += pageSize
        }
        var summary = RestoreSummary()
        try db.read { db in
            for id in entryIDs {
                if before[id] == true { summary.deletedEarlier += 1; continue }
                guard before[id] == nil, let row = try Row.fetchOne(db, sql: "SELECT canonical_id, deleted FROM entry WHERE id = ?", arguments: [id]),
                      row["deleted"] == 0 else { continue }
                if row["canonical_id"] as ToriID? == id { summary.imported += 1 } else { summary.merged += 1 }
            }
        }
        return summary
    }

    /// CSV export (§14.2): one row per live Entry. `containsWiktionary` tells the caller to add the attribution.
    public func exportCSV(utcOffsetMin: Int) throws -> (csv: String, containsWiktionary: Bool) {
        try read { r in
            let db = r.db
            var lines = ["text,translations,definitions,sentence,source,tags,stage,created"]
            let rows = try r.words(WordsQuery(sort: .alphabetical))
            for w in rows {
                let senses = try Row.fetchAll(db, sql: """
                    SELECT s.translation, s.definition FROM sense s WHERE s.canonical_entry_id = ? AND \(StoreReader.liveSense)
                    ORDER BY \(StoreReader.senseOrder)
                    """, arguments: [w.id])
                let context = try Row.fetchOne(db, sql: """
                    SELECT c.sentence, so.title, so.url FROM context c LEFT JOIN source s0 ON s0.id = c.source_id
                    LEFT JOIN source so ON so.id = s0.canonical_id
                    WHERE c.canonical_entry_id = ? AND c.deleted = 0 AND c.merged_into IS NULL ORDER BY c.captured_at, c.id LIMIT 1
                    """, arguments: [w.id])
                let day = DayModel.dayNumber(unixMs: w.createdAt, utcOffsetMin: utcOffsetMin)
                let date = ISO8601DateFormatter.string(from: Date(timeIntervalSince1970: Double(day) * 86_400),
                                                       timeZone: TimeZone(identifier: "UTC")!, formatOptions: [.withFullDate])
                let fields: [String] = [
                    w.text,
                    senses.compactMap { $0["translation"] as String? }.filter { !$0.isEmpty }.joined(separator: "; "),
                    senses.compactMap { $0["definition"] as String? }.filter { !$0.isEmpty }.joined(separator: "; "),
                    context?["sentence"] ?? "",
                    (context?["title"] as String?) ?? (context?["url"] as String?) ?? "",
                    try r.tags(of: w.id).map(\.name).joined(separator: "; "),
                    "\(w.stage)",
                    date,
                ]
                lines.append(fields.map(Self.csvField).joined(separator: ","))
            }
            let wiktionary = try Bool.fetchOne(db, sql: """
                SELECT EXISTS (SELECT 1 FROM sense s JOIN entry e ON e.id = s.canonical_entry_id WHERE \(StoreReader.liveSense)
                AND \(StoreReader.liveEntry) AND 'wiktionary' IN (s.translation_src, s.definition_src, s.pos_src))
                """) ?? false
            return (lines.joined(separator: "\r\n") + "\r\n", wiktionary)
        }
    }

    static func csvField(_ s: String) -> String {
        s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" })
            ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
    }
}
