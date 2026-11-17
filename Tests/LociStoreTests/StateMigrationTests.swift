import Foundation
import GRDB
import LociModel
import Testing

@testable import LociStore

struct StateMigrationTests {
  @Test func anAlphaOneDatabaseGainsConversationsAndRevisionsWithoutLosingPositions() throws {
    try DatabaseOpenTests.withFolder { folder in
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      let url = folder.appending(path: "loci.sqlite")
      let lesson = LessonRef(mentor: Fixture.id(1), lesson: Fixture.slug("intro"))
      let position = Locator.lesson(lesson, try TextQuote("position"))
      let state = ReadingState(position: position, finished: true, updatedAt: Fixture.instant)
      let old = try DatabaseQueue(path: url.path(percentEncoded: false))
      try Schema.migrator.migrate(old, upTo: "1 reading_state")
      try old.write { db in
        try db.execute(
          sql: "INSERT INTO reading_state VALUES (?, ?, ?, ?)",
          arguments: [ContentKey.key(.lesson(lesson)), position.description, true, Fixture.instant.description])
      }

      let upgraded = try StoreDatabase.open(at: url)
      #expect(try upgraded.readingState(of: .lesson(lesson)) == state)
      let conversation = ConversationRecord(id: Fixture.id(10), mentor: lesson.mentor, provider: .pi, session: nil)
      try upgraded.start(conversation, at: Fixture.instant)
      let message = Message(id: Fixture.id(20), at: Fixture.instant, body: .reply("hello"))
      try upgraded.append([message], to: conversation.id)
      #expect(try upgraded.see("old", of: lesson) == nil)
      #expect(try upgraded.see("new", of: lesson) == "old")

      let reopened = try StoreDatabase.open(at: url)
      #expect(try reopened.messages(of: lesson.mentor) == [message])
      #expect(try reopened.readingRecord(of: lesson.mentor).read == [lesson.lesson])
      #expect(try reopened.readingRecord(of: lesson.mentor).seen == [lesson.lesson: "new"])
    }
  }

  @Test func replacingMirrorsKeepsConversationsAndRevisionBaselines() throws {
    try DatabaseOpenTests.withFolder { folder in
      let url = folder.appending(path: "loci.sqlite")
      let database = try StoreDatabase.open(at: url)
      let mentor = Fixture.id(1)
      let lesson = LessonRef(mentor: mentor, lesson: Fixture.slug("intro"))
      let conversation = ConversationRecord(id: Fixture.id(10), mentor: mentor, provider: .pi, session: "session")
      let message = Message(id: Fixture.id(20), at: Fixture.instant, body: .reply("hello"))
      try database.start(conversation, at: Fixture.instant)
      try database.append([message], to: conversation.id)
      _ = try database.see("before", of: lesson)
      try database.queue.write { db in try db.execute(sql: "PRAGMA user_version = 0") }

      let reopened = try StoreDatabase.open(at: url)
      #expect(try reopened.latestConversation(of: mentor) == conversation)
      #expect(try reopened.messages(of: mentor) == [message])
      #expect(try reopened.see("after", of: lesson) == "before")
    }
  }

  @Test func lessonsWithTheSameSlugKeepSeparateReadingAndRevisionState() throws {
    let database = try StoreDatabase.inMemory()
    let first = LessonRef(mentor: Fixture.id(1), lesson: Fixture.slug("intro"))
    let other = LessonRef(mentor: Fixture.id(2), lesson: first.lesson)
    try database.save(ReadingState(position: nil, finished: true, updatedAt: Fixture.instant), for: .lesson(first))
    try database.save(ReadingState(position: nil, finished: false, updatedAt: Fixture.instant), for: .lesson(other))
    _ = try database.see("first", of: first)
    _ = try database.see("other", of: other)

    #expect(try database.readingRecord(of: first.mentor).read == [first.lesson])
    #expect(try database.readingRecord(of: other.mentor).read.isEmpty)
    #expect(try database.see("changed", of: first) == "first")
    #expect(try database.see("other", of: other) == nil)
    #expect(try database.readingRecord(of: other.mentor).seen == [other.lesson: "other"])
  }
}
