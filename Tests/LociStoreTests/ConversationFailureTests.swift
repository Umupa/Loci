import Foundation
import GRDB
import LociModel
import Testing

@testable import LociStore

struct ConversationFailureTests {
  private let mentor = Fixture.id(1)
  private var conversation: ConversationRecord {
    ConversationRecord(id: Fixture.id(10), mentor: mentor, provider: .pi, session: "session")
  }

  @Test func aDuplicateMessageRollsBackTheEntireAppend() throws {
    let database = try StoreDatabase.inMemory()
    try database.start(conversation, at: Fixture.instant)
    let original = Message(id: Fixture.id(20), at: Fixture.instant, body: .reply("original"))
    let fresh = Message(id: Fixture.id(21), at: Fixture.instant, body: .reply("new"))
    try database.append([original], to: conversation.id)

    #expect(throws: (any Error).self) { try database.append([fresh, original], to: conversation.id) }

    #expect(try database.messages(of: mentor) == [original])
    try database.append([fresh], to: conversation.id)
    #expect(try database.messages(of: mentor) == [original, fresh])
  }

  @Test func messagesCannotBeAppendedToAMissingConversation() throws {
    let database = try StoreDatabase.inMemory()
    #expect(throws: (any Error).self) {
      try database.append([Message(id: Fixture.id(20), at: Fixture.instant, body: .reply("lost"))], to: conversation.id)
    }
  }

  @Test func unreadableMessagesDoNotHideTheGoodOnes() throws {
    let database = try StoreDatabase.inMemory()
    try database.start(conversation, at: Fixture.instant)
    let messages = (20...24).map { Message(id: Fixture.id(UInt64($0)), at: Fixture.instant, body: .reply("\($0)")) }
    try database.append(messages, to: conversation.id)
    try database.queue.write { db in
      try db.execute(sql: "UPDATE message SET body = 'invalid' WHERE id = ?", arguments: [messages[1].id.description])
      try db.execute(sql: "UPDATE message SET at = 'invalid' WHERE id = ?", arguments: [messages[2].id.description])
      try db.execute(sql: "UPDATE message SET id = 'invalid' WHERE id = ?", arguments: [messages[3].id.description])
    }

    #expect(try database.messages(of: mentor) == [messages[0], messages[4]])
  }

  @Test func everyMessageBodyAndTheSessionSurviveReopening() throws {
    try DatabaseOpenTests.withFolder { folder in
      let url = folder.appending(path: "loci.sqlite")
      let database = try StoreDatabase.open(at: url)
      try database.start(conversation, at: Fixture.instant)
      let bodies: [Message.Body] = [
        .prompt(Prompt(text: "write", purpose: .writeLesson(Fixture.slug("intro")))),
        .thinking("consider"), .reply("answer"), .notice("notice"),
        .tool(ToolActivity(id: "tool", name: "read", kind: .read, subject: "a.md", output: "text", state: .failed)),
        .permission(
          PermissionAsk(
            id: "ask", title: "read", tool: "tool", options: [.init(id: "yes", role: .allowAlways, label: "Yes")],
            answer: .chosen("yes"))),
        .ended(.failed("quota")), .ended(.interrupted),
      ]
      let messages = bodies.enumerated().map {
        Message(id: Fixture.id(UInt64($0.offset + 20)), at: Fixture.instant, body: $0.element)
      }
      try database.append(messages, to: conversation.id)

      let reopened = try StoreDatabase.open(at: url)
      #expect(try reopened.latestConversation(of: mentor) == conversation)
      #expect(try reopened.messages(of: mentor) == messages)
      try reopened.deleteConversations(of: mentor)
      #expect(try StoreDatabase.open(at: url).messages(of: mentor).isEmpty)
    }
  }
}
