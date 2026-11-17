import GRDB

/// The database's tables, in two groups.
///
/// State that lives only in the database changes through migrations, which are only ever appended to.
/// Mirrors of the files are rebuilt instead: when `mirrorVersion` changes they are dropped and created
/// again, empty, until the next rebuild fills them.
enum Schema {
  static let mirrorVersion = 1

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
    return migrator
  }

  static let mirrorTables = ["mentor", "lesson", "citation", "item", "note", "search", "search_owner"]

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
      for table in mirrorTables { try db.execute(sql: "DROP TABLE IF EXISTS \(table)") }
      try createMirrors(db)
      try db.execute(sql: "PRAGMA user_version = \(mirrorVersion)")
    }
  }

  private static func createMirrors(_ db: Database) throws {
    try db.execute(
      sql: """
        CREATE TABLE mentor (
          id TEXT PRIMARY KEY NOT NULL,
          name TEXT NOT NULL,
          catalog_valid INTEGER NOT NULL,
          document TEXT NOT NULL
        );
        CREATE TABLE lesson (
          mentor_id TEXT NOT NULL,
          slug TEXT NOT NULL,
          chapter INTEGER,
          chapter_title TEXT,
          position INTEGER NOT NULL,
          title TEXT,
          written INTEGER NOT NULL,
          PRIMARY KEY (mentor_id, slug)
        );
        CREATE TABLE citation (
          mentor_id TEXT NOT NULL,
          slug TEXT NOT NULL,
          position INTEGER NOT NULL,
          item_id TEXT NOT NULL,
          anchor TEXT,
          PRIMARY KEY (mentor_id, slug, position)
        );
        CREATE INDEX citation_item ON citation(item_id);
        CREATE TABLE item (
          id TEXT PRIMARY KEY NOT NULL,
          kind TEXT NOT NULL,
          title TEXT NOT NULL,
          document TEXT NOT NULL
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
        CREATE VIRTUAL TABLE search USING fts5(
          target UNINDEXED, field UNINDEXED, original UNINDEXED, locator UNINDEXED, text,
          tokenize = 'unicode61 remove_diacritics 2'
        );
        """)
  }
}
