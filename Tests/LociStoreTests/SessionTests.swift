import Foundation
import LociModel
import Testing

@testable import LociStore

struct SessionTests {
  static func session(_ seed: UInt64, _ owner: SessionOwner = .conversation(.main), provider: Provider = .pi)
    -> SessionRecord
  {
    SessionRecord(
      id: Fixture.id(seed), owner: owner, runtime: Runtime(provider: provider, model: "m", effort: .high),
      instructions: "hash", startedAt: Fixture.instant)
  }

  static func message(_ seed: UInt64, _ body: Message.Body, at offset: Int64 = 0) -> Message {
    Message(
      id: Fixture.id(seed), at: Timestamp(millisecondsSince1970: Fixture.instant.millisecondsSince1970 + offset),
      body: body)
  }

  static let hi = Message.Body.prompt(Prompt(text: "Hi", purpose: .chat))

  @Test func aConversationsMessagesComeBackInOrderAcrossItsSessions() throws {
    let database = try StoreDatabase.inMemory()
    try database.start(Self.session(10))
    try database.append([Self.message(30, Self.hi), Self.message(20, .reply("Hello"))], to: Fixture.id(10))
    try database.start(Self.session(11, provider: .grok))
    try database.start(Self.session(12, .conversation(.item(Fixture.id(2)))))
    try database.append([Self.message(25, .startedOver)], to: Fixture.id(11))
    try database.append([Self.message(26, .reply("elsewhere"))], to: Fixture.id(12))

    #expect(try database.messages(of: .conversation(.main)).map(\.body) == [Self.hi, .reply("Hello"), .startedOver])
    #expect(try database.latestSession(of: .conversation(.main)) == Self.session(11, provider: .grok))
    #expect(try database.latestSession(of: .review(Day("2026-11-18")!)) == nil)
  }

  @Test func aNewSessionTakesOverAPromptAndASessionLeftEmptyIsGone() throws {
    let database = try StoreDatabase.inMemory()
    try database.start(Self.session(10))
    try database.append([Self.message(30, Self.hi), Self.message(31, .reply("Hello"))], to: Fixture.id(10))
    try database.start(Self.session(11))
    try database.append([Self.message(32, Self.hi)], to: Fixture.id(11))

    try database.start(Self.session(12), taking: [Fixture.id(32)])
    try database.append([Self.message(33, .reply("Again"))], to: Fixture.id(12))
    try database.start(Self.session(13), taking: [Fixture.id(33)])

    #expect(
      try database.messages(of: .conversation(.main)).map(\.body) == [
        Self.hi, .reply("Hello"), Self.hi, .reply("Again"),
      ])
    let left = try database.queue.read { db in try String.fetchAll(db, sql: "SELECT id FROM session ORDER BY seq") }
    #expect(left == [Fixture.id(10), Fixture.id(12), Fixture.id(13)].map(\.description))
  }

  @Test func aSessionKeepsItsHandleAndWhatItWasShown() throws {
    let database = try StoreDatabase.inMemory()
    try database.start(Self.session(10, .review(Day("2026-11-18")!)))

    try database.bind(handle: "pi-session", to: Fixture.id(10))
    try database.markSent(["MEMORY.md": "abc"], in: Fixture.id(10))

    let session = try #require(try database.latestSession(of: .review(Day("2026-11-18")!)))
    #expect(session.handle == "pi-session")
    #expect(session.sent == ["MEMORY.md": "abc"])
    #expect(session.runtime == Runtime(provider: .pi, model: "m", effort: .high))
  }

  @Test func deletingAnItemsConversationLeavesTheOthers() throws {
    let database = try StoreDatabase.inMemory()
    let item = Fixture.id(2)
    try database.start(Self.session(10))
    try database.start(Self.session(11, .conversation(.item(item))))
    try database.append([Self.message(30, .reply("main"))], to: Fixture.id(10))
    try database.append([Self.message(31, .reply("item"))], to: Fixture.id(11))

    try database.deleteConversation(on: item)

    #expect(try database.messages(of: .conversation(.item(item))).isEmpty)
    #expect(try database.latestSession(of: .conversation(.item(item))) == nil)
    #expect(try database.messages(of: .conversation(.main)).map(\.body) == [.reply("main")])
  }

  @Test func talkCountsWhatThePersonTypedOutsideReviewsAndPanelRefreshes() throws {
    let database = try StoreDatabase.inMemory()
    try database.start(Self.session(10))
    try database.start(Self.session(11, .conversation(.item(Fixture.id(2)))))
    try database.start(Self.session(12, .conversation(.item(Fixture.id(3)))))
    try database.start(Self.session(13, .review(Day("2026-11-18")!)))
    try database.start(Self.session(14, .panel("sandbox-radar")))
    try database.append(
      [Self.message(34, .prompt(Prompt(text: "refresh", purpose: .panel("sandbox-radar"))), at: 30)],
      to: Fixture.id(14))
    try database.append([Self.message(30, Self.hi, at: 5), Self.message(31, .reply("yo"))], to: Fixture.id(10))
    try database.append([Self.message(32, Self.hi, at: 9)], to: Fixture.id(11))
    try database.append(
      [Self.message(33, .prompt(Prompt(text: "look back", purpose: .review(Day("2026-11-18")!))), at: 20)],
      to: Fixture.id(13))

    let talk = try database.talk()
    #expect(talk.messages == 2)
    #expect(talk.itemsTalkedAbout == 1)
    #expect(talk.first == Timestamp(millisecondsSince1970: Fixture.instant.millisecondsSince1970 + 5))
    #expect(talk.latest == Timestamp(millisecondsSince1970: Fixture.instant.millisecondsSince1970 + 9))
    let start = Fixture.instant
    #expect(
      try database.typedMessages(from: start, to: Timestamp(millisecondsSince1970: start.millisecondsSince1970 + 6))
        == 1)
  }

  @Test func aDuplicateMessageRollsBackTheEntireAppend() throws {
    let database = try StoreDatabase.inMemory()
    try database.start(Self.session(10))
    let original = Self.message(20, .reply("original"))
    let fresh = Self.message(21, .reply("new"))
    try database.append([original], to: Fixture.id(10))

    #expect(throws: (any Error).self) { try database.append([fresh, original], to: Fixture.id(10)) }

    #expect(try database.messages(of: .conversation(.main)) == [original])
  }

  @Test func messagesCannotBeAppendedToAMissingSession() throws {
    let database = try StoreDatabase.inMemory()
    #expect(throws: (any Error).self) { try database.append([Self.message(20, .reply("lost"))], to: Fixture.id(10)) }
  }

  @Test func unreadableMessagesDoNotHideTheGoodOnes() throws {
    let database = try StoreDatabase.inMemory()
    try database.start(Self.session(10))
    let messages = (20...24).map { Self.message(UInt64($0), .reply("\($0)")) }
    try database.append(messages, to: Fixture.id(10))
    try database.queue.write { db in
      try db.execute(sql: "UPDATE message SET body = 'invalid' WHERE id = ?", arguments: [messages[1].id.description])
      try db.execute(sql: "UPDATE message SET at = 'invalid' WHERE id = ?", arguments: [messages[2].id.description])
      try db.execute(sql: "UPDATE message SET id = 'invalid' WHERE id = ?", arguments: [messages[3].id.description])
    }

    #expect(try database.messages(of: .conversation(.main)) == [messages[0], messages[4]])
  }

  @Test func everyMessageBodySurvivesReopening() throws {
    try DatabaseOpenTests.withFolder { folder in
      let url = folder.appending(path: "loci.sqlite")
      let database = try StoreDatabase.open(at: url)
      try database.start(Self.session(10))
      let bodies: [Message.Body] = [
        .prompt(Prompt(text: "look back", purpose: .review(Day("2026-11-18")!))), .thinking("consider"),
        .prompt(Prompt(text: "refresh", purpose: .panel("sandbox-radar"))),
        .reply("answer"), .notice("notice"),
        .tool(ToolActivity(id: "tool", name: "read", kind: .read, subject: "a.md", output: "text", state: .failed)),
        .prompt(
          Prompt(
            text: "why", purpose: .chat,
            passage: QuotedPassage(
              locator: .item(Fixture.id(30), .quote(try TextQuote("a"))), excerpt: "a b", note: Fixture.id(31)))),
        .savedToNote(Fixture.id(31)), .ended(.failed("quota")), .ended(.interrupted), .startedOver,
      ]
      let messages = bodies.enumerated().map { Self.message(UInt64($0.offset + 20), $0.element) }
      try database.append(messages, to: Fixture.id(10))

      #expect(try StoreDatabase.open(at: url).messages(of: .conversation(.main)) == messages)
    }
  }
}
