import Foundation
import GRDB
import LociModel
import Testing

@testable import LociStore

struct ItemConversationTests {
  private let ada = Fixture.id(1)
  private let alan = Fixture.id(2)
  private let paper = Fixture.id(5)

  private func message(_ seed: UInt64, _ text: String) -> Message {
    Message(id: Fixture.id(seed), at: Fixture.instant, body: .reply(text))
  }

  @Test func anItemsConversationIsEveryMentorsAnswersThereInOrder() throws {
    let database = try StoreDatabase.inMemory()
    try database.start(
      ConversationRecord(id: Fixture.id(10), mentor: ada, item: paper, provider: .pi, session: nil), at: Fixture.instant
    )
    try database.start(
      ConversationRecord(id: Fixture.id(11), mentor: alan, item: paper, provider: .pi, session: nil),
      at: Fixture.instant)
    try database.append([message(20, "first")], to: Fixture.id(10))
    try database.append([message(21, "second")], to: Fixture.id(11))
    try database.append([message(22, "third")], to: Fixture.id(10))

    #expect(
      try database.messages(on: paper) == [
        AttributedMessage(mentor: ada, message: message(20, "first")),
        AttributedMessage(mentor: alan, message: message(21, "second")),
        AttributedMessage(mentor: ada, message: message(22, "third")),
      ])
    #expect(try database.messages(of: ada, on: paper).map(\.body) == [.reply("first"), .reply("third")])
  }

  @Test func aMentorsOwnConversationAndItsAnswersOnItemsAreKeptApart() throws {
    let database = try StoreDatabase.inMemory()
    let own = ConversationRecord(id: Fixture.id(10), mentor: ada, provider: .pi, session: "course")
    let onPaper = ConversationRecord(id: Fixture.id(11), mentor: ada, item: paper, provider: .pi, session: "paper")
    try database.start(own, at: Fixture.instant)
    try database.start(onPaper, at: Fixture.instant)
    try database.append([message(20, "course")], to: own.id)
    try database.append([message(21, "paper")], to: onPaper.id)

    #expect(try database.messages(of: ada).map(\.body) == [.reply("course")])
    #expect(try database.latestConversation(of: ada) == own)
    #expect(try database.latestConversation(of: ada, on: paper) == onPaper)
  }

  @Test func deletingAMentorKeepsWhatItAnsweredOnItems() throws {
    let database = try StoreDatabase.inMemory()
    try database.start(
      ConversationRecord(id: Fixture.id(10), mentor: ada, provider: .pi, session: nil), at: Fixture.instant)
    try database.start(
      ConversationRecord(id: Fixture.id(11), mentor: ada, item: paper, provider: .pi, session: nil), at: Fixture.instant
    )
    try database.append([message(20, "course")], to: Fixture.id(10))
    try database.append([message(21, "paper")], to: Fixture.id(11))

    try database.deleteConversations(of: ada)

    #expect(try database.messages(of: ada).isEmpty)
    #expect(try database.messages(on: paper).map(\.message.body) == [.reply("paper")])
  }

  @Test func deletingAnItemTakesItsConversationAndCompanion() throws {
    let database = try StoreDatabase.inMemory()
    try database.start(
      ConversationRecord(id: Fixture.id(11), mentor: ada, item: paper, provider: .pi, session: nil), at: Fixture.instant
    )
    try database.append([message(21, "paper")], to: Fixture.id(11))
    try database.choose(companion: ada, on: paper, at: Fixture.instant)

    try database.deleteConversations(on: paper)

    #expect(try database.messages(on: paper).isEmpty)
    #expect(try database.latestConversation(of: ada, on: paper) == nil)
    #expect(try database.companion(on: paper) == nil)
  }

  @Test func theCompanionChosenOnAnItemIsRememberedAndOfferedOnNewItems() throws {
    let database = try StoreDatabase.inMemory()
    let other = Fixture.id(6)
    #expect(try database.companion(on: paper) == nil)

    try database.choose(companion: ada, on: paper, at: Fixture.instant)
    try database.choose(companion: alan, on: other, at: Fixture.instant)

    #expect(try database.companion(on: paper) == ada)
    #expect(try database.companion(on: other) == alan)
    #expect(try database.companion(on: Fixture.id(7)) == alan)
    try database.choose(companion: ada, on: other, at: Fixture.instant)
    #expect(try database.companion(on: Fixture.id(7)) == ada)
  }

  @Test func anOlderDatabaseKeepsItsConversationsWhenItGainsItemConversations() throws {
    try DatabaseOpenTests.withFolder { folder in
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      let url = folder.appending(path: "loci.sqlite")
      let old = try DatabaseQueue(path: url.path(percentEncoded: false))
      try Schema.migrator.migrate(old, upTo: "3 seen_lesson")
      try old.write { db in
        try db.execute(
          sql: "INSERT INTO conversation (id, mentor_id, provider, session, started_at) VALUES (?, ?, 'pi', 's', ?)",
          arguments: [Fixture.id(10).description, ada.description, Fixture.instant.description])
      }
      try old.close()

      let upgraded = try StoreDatabase.open(at: url)
      #expect(
        try upgraded.latestConversation(of: ada)
          == ConversationRecord(id: Fixture.id(10), mentor: ada, provider: .pi, session: "s"))
    }
  }
}
