import GRDB

/// The database's tables, in two groups.
///
/// State that lives only in the database changes through migrations, which are only ever appended to.
/// Mirrors of the files are rebuilt instead: when `mirrorVersion` changes they are dropped and created
/// again, empty, until the next rebuild fills them.
enum Schema {
  static let mirrorVersion = 4

  static var migrator: DatabaseMigrator {
    var migrator = DatabaseMigrator()
    migrator.registerMigration("1 reading_state") { db in
      try db.execute(
        sql: """
          CREATE TABLE reading_state (
            content TEXT PRIMARY KEY NOT NULL,
            position TEXT,
            finished INTEGER NOT NULL,
            updated_at TEXT NOT NULL
          )
          """)
    }
    migrator.registerMigration("2 conversation") { db in
      try db.execute(
        sql: """
          CREATE TABLE conversation (
            seq INTEGER PRIMARY KEY AUTOINCREMENT,
            id TEXT NOT NULL UNIQUE,
            mentor_id TEXT NOT NULL,
            provider TEXT NOT NULL,
            session TEXT,
            started_at TEXT NOT NULL
          );
          CREATE INDEX conversation_mentor ON conversation(mentor_id);
          CREATE TABLE message (
            seq INTEGER PRIMARY KEY AUTOINCREMENT,
            id TEXT NOT NULL UNIQUE,
            conversation_id TEXT NOT NULL REFERENCES conversation(id),
            at TEXT NOT NULL,
            body TEXT NOT NULL
          );
          CREATE INDEX message_conversation ON message(conversation_id);
          """)
    }
    migrator.registerMigration("3 seen_lesson") { db in
      try db.execute(
        sql: """
          CREATE TABLE seen_lesson (
            content TEXT PRIMARY KEY NOT NULL,
            text TEXT NOT NULL
          )
          """)
    }
    migrator.registerMigration("4 job") { db in
      try db.execute(
        sql: """
          CREATE TABLE job (
            item_id TEXT PRIMARY KEY NOT NULL,
            stage TEXT NOT NULL,
            state TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
          """)
    }
    migrator.registerMigration("5 item conversation") { db in
      try db.execute(
        sql: """
          ALTER TABLE conversation ADD COLUMN item_id TEXT;
          CREATE INDEX conversation_item ON conversation(item_id);
          CREATE TABLE companion (
            item_id TEXT PRIMARY KEY NOT NULL,
            mentor_id TEXT NOT NULL,
            chosen_at TEXT NOT NULL
          );
          """)
    }
    migrator.registerMigration("6 loci") { db in
      try db.execute(
        sql: """
          DROP TABLE message;
          DROP TABLE conversation;
          DROP TABLE companion;
          DROP TABLE seen_lesson;
          CREATE TABLE session (
            seq INTEGER PRIMARY KEY AUTOINCREMENT,
            id TEXT NOT NULL UNIQUE,
            owner TEXT NOT NULL,
            provider TEXT NOT NULL,
            model TEXT,
            effort TEXT,
            handle TEXT,
            instructions TEXT NOT NULL,
            sent TEXT NOT NULL,
            started_at TEXT NOT NULL
          );
          CREATE INDEX session_owner ON session(owner);
          CREATE TABLE message (
            seq INTEGER PRIMARY KEY AUTOINCREMENT,
            id TEXT NOT NULL UNIQUE,
            session_id TEXT NOT NULL REFERENCES session(id),
            at TEXT NOT NULL,
            typed INTEGER NOT NULL,
            body TEXT NOT NULL
          );
          CREATE INDEX message_session ON message(session_id);
          CREATE TABLE event (
            seq INTEGER PRIMARY KEY AUTOINCREMENT,
            id TEXT NOT NULL UNIQUE,
            at TEXT NOT NULL,
            item_id TEXT NOT NULL,
            body TEXT NOT NULL
          );
          CREATE INDEX event_item ON event(item_id);
          CREATE TABLE review (
            day TEXT PRIMARY KEY NOT NULL,
            started_at TEXT NOT NULL,
            outcome TEXT
          );
          """)
    }
    migrator.registerMigration("7 paused job") { db in
      try db.execute(sql: #"UPDATE job SET state = '{"paused":{}}' WHERE state = '{"stopped":{}}'"#)
    }
    migrator.registerMigration("8 timers") { db in
      try db.execute(
        sql: """
          CREATE TABLE timer (
            id TEXT PRIMARY KEY NOT NULL,
            kind TEXT NOT NULL,
            name TEXT UNIQUE,
            body TEXT NOT NULL,
            due_at TEXT,
            ended_at TEXT
          );
          CREATE TABLE inbox (
            seq INTEGER PRIMARY KEY AUTOINCREMENT,
            id TEXT NOT NULL UNIQUE,
            key TEXT NOT NULL UNIQUE,
            open INTEGER NOT NULL,
            body TEXT NOT NULL
          );
          CREATE INDEX inbox_open ON inbox(open);
          CREATE TABLE run (
            id TEXT PRIMARY KEY NOT NULL,
            started_at TEXT NOT NULL,
            body TEXT NOT NULL,
            told_at TEXT
          );
          CREATE TABLE run_schedule (
            run_id TEXT NOT NULL REFERENCES run(id),
            schedule TEXT NOT NULL,
            PRIMARY KEY (run_id, schedule)
          );
          CREATE INDEX run_schedule_schedule ON run_schedule(schedule);
          """)
    }
    migrator.registerMigration("9 connectors") { db in
      try db.execute(
        sql: """
          CREATE TABLE connector (
            id TEXT PRIMARY KEY NOT NULL,
            body TEXT NOT NULL
          );
          CREATE TABLE connector_call (
            seq INTEGER PRIMARY KEY AUTOINCREMENT,
            id TEXT NOT NULL UNIQUE,
            at TEXT NOT NULL,
            connector TEXT NOT NULL,
            caller TEXT NOT NULL,
            body TEXT NOT NULL
          );
          CREATE INDEX connector_call_at ON connector_call(at);
          CREATE INDEX connector_call_caller ON connector_call(caller);
          """)
    }
    migrator.registerMigration("10 connector set aside") { db in
      try db.execute(sql: "CREATE TABLE connector_set_aside (id TEXT PRIMARY KEY NOT NULL)")
    }
    migrator.registerMigration("11 sources") { db in
      try db.execute(
        sql: """
          CREATE TABLE source_snapshot (
            source TEXT PRIMARY KEY NOT NULL,
            body TEXT NOT NULL
          );
          CREATE TABLE source_series (
            seq INTEGER PRIMARY KEY AUTOINCREMENT,
            source TEXT NOT NULL,
            record TEXT NOT NULL,
            at TEXT NOT NULL,
            body TEXT NOT NULL
          );
          CREATE INDEX source_series_key ON source_series(source, record, at);
          """)
    }
    return migrator
  }

  static let mirrorTables = [
    "course_lesson", "course", "item", "note", "search", "search_owner", "transcript", "transcript_file",
  ]
  /// Mirrors an earlier version kept, dropped with the others when `mirrorVersion` changes.
  static let retiredMirrorTables = ["mentor", "lesson", "citation"]

  static func prepare(_ queue: DatabaseQueue) throws {
    let migrator = migrator
    let health = try queue.read { db in
      (try String.fetchOne(db, sql: "PRAGMA quick_check"), try migrator.appliedIdentifiers(db))
    }
    guard health.0 == "ok" else { throw DatabaseOpenError.unreadable(health.0 ?? "integrity check gave no answer") }
    let unknown = health.1.subtracting(migrator.migrations)
    guard unknown.isEmpty else { throw DatabaseOpenError.newerVersion(unknownMigrations: unknown.sorted()) }
    try migrator.migrate(queue)
    try queue.write { db in
      guard try Int.fetchOne(db, sql: "PRAGMA user_version") != mirrorVersion else { return }
      for table in mirrorTables + retiredMirrorTables { try db.execute(sql: "DROP TABLE IF EXISTS \(table)") }
      try createMirrors(db)
      try db.execute(sql: "PRAGMA user_version = \(mirrorVersion)")
    }
  }

  private static func createMirrors(_ db: Database) throws {
    try db.execute(
      sql: """
        CREATE TABLE item (
          id TEXT PRIMARY KEY NOT NULL,
          kind TEXT NOT NULL,
          title TEXT NOT NULL,
          document TEXT NOT NULL
        );
        CREATE TABLE course (
          id TEXT PRIMARY KEY NOT NULL,
          created_at TEXT NOT NULL,
          document TEXT NOT NULL
        );
        CREATE TABLE course_lesson (
          course_id TEXT NOT NULL REFERENCES course(id),
          id TEXT NOT NULL,
          position INTEGER NOT NULL,
          document TEXT NOT NULL,
          PRIMARY KEY (course_id, id)
        );
        CREATE TABLE note (
          id TEXT PRIMARY KEY NOT NULL,
          content TEXT NOT NULL,
          position INTEGER NOT NULL,
          document TEXT NOT NULL
        );
        CREATE INDEX note_content ON note(content);
        CREATE TABLE search_owner (
          search_rowid INTEGER PRIMARY KEY NOT NULL,
          owner TEXT NOT NULL
        );
        CREATE INDEX search_owner_owner ON search_owner(owner);
        CREATE VIRTUAL TABLE transcript USING fts5(
          original UNINDEXED, text, tokenize = 'unicode61 remove_diacritics 2'
        );
        CREATE TABLE transcript_file (
          transcript_rowid INTEGER PRIMARY KEY NOT NULL,
          path TEXT NOT NULL
        );
        CREATE INDEX transcript_file_path ON transcript_file(path);
        CREATE VIRTUAL TABLE search USING fts5(
          target UNINDEXED, field UNINDEXED, original UNINDEXED, locator UNINDEXED, text,
          tokenize = 'unicode61 remove_diacritics 2'
        );
        """)
  }
}
