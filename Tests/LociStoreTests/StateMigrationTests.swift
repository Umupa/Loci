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
}
