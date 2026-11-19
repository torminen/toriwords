import GRDB

/// `user.sqlite` schema. Synced columns are nullable so a tombstone can drop field values.
enum Schema {
    static let version = 1

    static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            for sql in v1 { try db.execute(sql: sql) }
            try db.execute(sql: "INSERT INTO schema_meta (version) VALUES (1)")
        }
        // No own backend: CloudKit system fields per record; the account and cursor keys of the old sync go.
        m.registerMigration("v2-cloud") { db in
            try db.execute(sql: "CREATE TABLE cloud_record_meta (record_id BLOB PRIMARY KEY, system_fields BLOB NOT NULL)")
            try db.execute(sql: """
                DELETE FROM sync_state WHERE key IN
                ('cursor','accountId','lastSyncedAccountId','pendingAccountChoice','adoptedAccountId','lastProvider','signInBaseline')
                """)
        }
        return m
    }

    private static let sync = """
        field_clocks TEXT NOT NULL DEFAULT '{}', deleted INTEGER NOT NULL DEFAULT 0, merged_into BLOB,
        extra TEXT, schema INTEGER NOT NULL DEFAULT 1
        """

    private static let v1 = [
        "CREATE TABLE language_pair (id BLOB PRIMARY KEY, native_lang TEXT, target_lang TEXT, created_at INTEGER, \(sync))",
        """
        CREATE TABLE entry (id BLOB PRIMARY KEY, language_pair_id BLOB, text TEXT, ipa TEXT, note TEXT, status TEXT,
          excluded_reason TEXT, enrichment_status TEXT, needs_check INTEGER, origin TEXT, created_at INTEGER, updated_at INTEGER,
          match_key TEXT, text_fold TEXT, canonical_id BLOB, enrich_attempts INTEGER NOT NULL DEFAULT 0, \(sync))
        """,
        "CREATE INDEX entry_key ON entry (language_pair_id, match_key)",
        "CREATE INDEX entry_canonical ON entry (canonical_id)",
        "CREATE INDEX entry_created ON entry (created_at)",
        "CREATE INDEX entry_status ON entry (status)",
        """
        CREATE TABLE sense (id BLOB PRIMARY KEY, entry_id BLOB, translation TEXT, definition TEXT, part_of_speech TEXT,
          position REAL, translation_src TEXT, definition_src TEXT, pos_src TEXT, dict_version TEXT, dict_headword_key TEXT,
          dict_sense_ordinal INTEGER, translation_fold TEXT, definition_fold TEXT, canonical_id BLOB, canonical_entry_id BLOB, \(sync))
        """,
        "CREATE INDEX sense_entry ON sense (canonical_entry_id)",
        "CREATE INDEX sense_owner ON sense (entry_id)",
        """
        CREATE TABLE source (id BLOB PRIMARY KEY, kind TEXT, url TEXT, title TEXT, app TEXT, url_key TEXT, canonical_id BLOB, \(sync))
        """,
        """
        CREATE TABLE context (id BLOB PRIMARY KEY, entry_id BLOB, sense_id BLOB, sentence TEXT, highlight_offset INTEGER,
          highlight_length INTEGER, source_id BLOB, captured_at INTEGER, sentence_fold TEXT, canonical_id BLOB,
          canonical_entry_id BLOB, \(sync))
        """,
        "CREATE INDEX context_entry ON context (canonical_entry_id)",
        "CREATE INDEX context_owner ON context (entry_id)",
        """
        CREATE TABLE card (id BLOB PRIMARY KEY, entry_id BLOB, direction TEXT, import_ref TEXT, created_at INTEGER,
          stability REAL, difficulty REAL, last_review_day INTEGER, due_day INTEGER, reps INTEGER, lapses INTEGER,
          stage TEXT, params_id TEXT, canonical_entry_id BLOB, canonical_card_id BLOB, \(sync))
        """,
        "CREATE INDEX card_due ON card (due_day)",
        "CREATE INDEX card_canonical ON card (canonical_card_id)",
        "CREATE INDEX card_entry ON card (canonical_entry_id)",
        "CREATE INDEX card_owner ON card (entry_id)",
        """
        CREATE TABLE review_log (id BLOB PRIMARY KEY, card_id BLOB, owner_entry_id BLOB, reviewed_at INTEGER,
          utc_offset_min INTEGER, rating INTEGER, answer_ms INTEGER, device_id BLOB, original_rating INTEGER, import_ref TEXT,
          review_day INTEGER, review_type TEXT, canonical_card_id BLOB, \(sync))
        """,
        "CREATE INDEX review_log_card ON review_log (canonical_card_id, reviewed_at, id)",
        "CREATE INDEX review_log_day ON review_log (review_day)",
        "CREATE INDEX review_log_raw_card ON review_log (card_id)",
        "CREATE INDEX review_log_owner ON review_log (owner_entry_id)",
        "CREATE TABLE tag (id BLOB PRIMARY KEY, name TEXT, name_key TEXT, canonical_id BLOB, \(sync))",
        "CREATE INDEX tag_key ON tag (name_key)",
        """
        CREATE TABLE entry_tag (id BLOB PRIMARY KEY, entry_id BLOB, tag_id BLOB, present INTEGER,
          canonical_entry_id BLOB, canonical_tag_id BLOB, \(sync))
        """,
        "CREATE INDEX entry_tag_entry ON entry_tag (canonical_entry_id)",
        "CREATE INDEX entry_tag_owner ON entry_tag (entry_id)",
        "CREATE INDEX entry_tag_tag ON entry_tag (tag_id)",
        """
        CREATE TABLE settings (id BLOB PRIMARY KEY, new_words_per_day INTEGER, desired_retention REAL, fsrs_w TEXT,
          params_id TEXT, scheduler_version INTEGER, \(sync))
        """,
        """
        CREATE TABLE device (id BLOB PRIMARY KEY, platform TEXT, display_name TEXT, first_seen INTEGER,
          is_this_device INTEGER NOT NULL DEFAULT 0, \(sync))
        """,
        """
        CREATE TABLE pending_changes (record_id BLOB NOT NULL, type TEXT NOT NULL, field TEXT NOT NULL, clock TEXT NOT NULL,
          PRIMARY KEY (record_id, field))
        """,
        "CREATE TABLE sync_state (key TEXT PRIMARY KEY, value TEXT)",
        "CREATE TABLE inbox_import (inbox_id BLOB PRIMARY KEY, imported_at INTEGER NOT NULL)",
        "CREATE TABLE schema_meta (version INTEGER NOT NULL)",
    ]
}
