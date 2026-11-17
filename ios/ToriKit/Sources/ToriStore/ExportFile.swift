import Foundation

/// Settings → Data → Export (doc 36 §14.2, doc 35 §3.11): the two formats and the file handed to the share sheet.
public enum ExportFormat: String, CaseIterable, Sendable {
    /// "Backup (JSON)": everything, restorable.
    case backup
    /// "Spreadsheet (CSV)": one row per word, lossy.
    case csv
}

public enum ExportFile {
    /// Used when the bundled dictionary's own `meta.licence_text` is not available (doc 36 §8.4).
    public static let defaultAttribution = """
        Dictionary data from Wiktionary (en.wiktionary.org, ru.wiktionary.org), Wiktionary contributors, \
        CC BY-SA 4.0 (https://creativecommons.org/licenses/by-sa/4.0/), extracted with wiktextract (kaikki.org). \
        Modified: filtered, merged, normalised.
        """

    /// `ToriWords-backup-2026-11-17.json` / `ToriWords-2026-11-17.csv`, dated in the device's time zone.
    public static func name(_ format: ExportFormat, at date: Date, timeZone: TimeZone = .current) -> String {
        let day = ISO8601DateFormatter.string(from: date, timeZone: timeZone, formatOptions: [.withFullDate])
        return switch format {
        case .backup: "ToriWords-backup-\(day).json"
        case .csv: "ToriWords-\(day).csv"
        }
    }

    /// The file's bytes. The CSV gets the attribution as its last row only when it contains Wiktionary-derived text.
    public static func data(_ format: ExportFormat, from store: ToriStore, attribution: String, utcOffsetMin: Int) throws -> Data {
        switch format {
        case .backup:
            return try store.exportBackup(attribution: attribution)
        case .csv:
            let (csv, wiktionary) = try store.exportCSV(utcOffsetMin: utcOffsetMin)
            // ponytail: attribution as a trailing one-cell row (form is Architecture AQ-11); spreadsheets show it last.
            return Data((wiktionary ? csv + ToriStore.csvField(attribution) + "\r\n" : csv).utf8)
        }
    }
}

extension ToriStore {
    /// Settings → New words per day (Product §5.9): counts words, not cards.
    public static let newWordsPerDayRange = 0...50
}
