import Foundation
import GRDB
import LociModel
import Testing

@testable import LociStore

struct StateMigrationTests {
  @Test func aMentorDatabaseKeepsReadingPositionsAndDropsMentorConversations() throws {
    try DatabaseOpenTests.withFolder { folder in
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      let url = folder.appending(path: "loci.sqlite")
      let content = ContentRef.item(Fixture.id(3))
      let state = ReadingState(position: nil, finished: true, updatedAt: Fixture.instant)
      let old = try DatabaseQueue(path: url.path(percentEncoded: false))
      try Schema.migrator.migrate(old, upTo: "5 item conversation")
      try old.write { db in
        try db.execute(
          sql: "INSERT INTO reading_state VALUES (?, ?, ?, ?)",
          arguments: [ContentKey.key(content), nil, true, Fixture.instant.description])
        try db.execute(
          sql: "INSERT INTO conversation (id, mentor_id, provider, started_at) VALUES ('c', 'm', 'pi', 'now')")
        try db.execute(sql: "PRAGMA user_version = 1")
      }

      let upgraded = try StoreDatabase.open(at: url)

      #expect(try upgraded.readingState(of: content) == state)
      #expect(try upgraded.messages(of: .conversation(.main)).isEmpty)
      let tables = try upgraded.queue.read { db in try String.fetchAll(db, sql: "SELECT name FROM sqlite_master") }
      #expect(!tables.contains("conversation") && !tables.contains("companion") && !tables.contains("mentor"))
    }
  }

  @Test func replacingMirrorsKeepsConversations() throws {
    try DatabaseOpenTests.withFolder { folder in
      let url = folder.appending(path: "loci.sqlite")
      let database = try StoreDatabase.open(at: url)
      let message = Message(id: Fixture.id(20), at: Fixture.instant, body: .reply("hello"))
      try database.start(SessionTests.session(10))
      try database.append([message], to: Fixture.id(10))
      try database.queue.write { db in try db.execute(sql: "PRAGMA user_version = 0") }

      let reopened = try StoreDatabase.open(at: url)
      #expect(try reopened.latestSession(of: .conversation(.main)) == SessionTests.session(10))
      #expect(try reopened.messages(of: .conversation(.main)) == [message])
    }
  }

  /// A database as version 11 left it, with a source's snapshot and an event of the chat's in the inbox.
  @Test func aDatabaseWithSourcesKeepsTheirSnapshotsAndItsChatEventsAndTakesEntries() throws {
    try DatabaseOpenTests.withFolder { folder in
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      let url = folder.appending(path: "loci.sqlite")
      let key = SourceKey(.chat, "prem")
      let snapshot = SourceSnapshot(fetched: Fixture.instant, records: ["513870": ["premium": .number(0.159)]])
      let event = Event(id: Fixture.id(4), source: .followUp(Fixture.id(5), project: nil), due: Fixture.instant)
      let old = try DatabaseQueue(path: url.path(percentEncoded: false))
      try Schema.migrator.migrate(old, upTo: "11 sources")
      try old.write { db in
        try db.execute(
          sql: "INSERT INTO source_snapshot (source, body) VALUES (?, ?)",
          arguments: [
            key.description,
            #"{"fetched":"\#(Fixture.instant)","tried":"\#(Fixture.instant)","failures":0,"records":{"513870":{"premium":0.159}}}"#,
          ])
        try db.execute(
          sql: "INSERT INTO inbox (id, key, open, body) VALUES (?, ?, 1, ?)",
          arguments: [event.id.description, event.key, try MirrorUpdate.json(event)])
      }

      let upgraded = try StoreDatabase.open(at: url)

      #expect(try upgraded.sourceSnapshot(key) == snapshot)
      #expect(try upgraded.openEvents().map(\.source.home) == [.chat])
      #expect(try upgraded.recordEntries(key, [SourceEntry(id: "a", title: "x")], at: Fixture.instant).count == 1)
    }
  }

  /// A database as version 12 left it, with a source's entries.
  @Test func aDatabaseWithEntriesKeepsThemInTheOrderTheyCame() throws {
    try DatabaseOpenTests.withFolder { folder in
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      let url = folder.appending(path: "loci.sqlite")
      let key = SourceKey(.chat, "news")
      let old = try DatabaseQueue(path: url.path(percentEncoded: false))
      try Schema.migrator.migrate(old, upTo: "12 source entries")
      try old.write { db in
        for id in ["a", "b"] {
          try db.execute(
            sql: "INSERT INTO source_entry (source, id, seen, body) VALUES (?, ?, ?, ?)",
            arguments: [key.description, id, Fixture.instant.description, #"{"id":"\#(id)","title":"条目 \#(id)"}"#])
        }
      }

      let upgraded = try StoreDatabase.open(at: url)

      let kept = try upgraded.sourceEntries(key, after: nil, limit: 10)
      #expect(kept.map(\.entry) == [SourceEntry(id: "a", title: "条目 a"), SourceEntry(id: "b", title: "条目 b")])
      #expect(try upgraded.sourceEntries(key, after: kept[0].seq, limit: 10).map(\.entry.id) == ["b"])
    }
  }
}
