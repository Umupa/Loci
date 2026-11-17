import Foundation
import LociModel
import Testing

@testable import LociStore

struct ConversationTests {
  private let mentor = Fixture.id(1)

  private func message(_ seed: UInt64, _ body: Message.Body) -> Message {
    Message(id: Fixture.id(seed), at: Fixture.instant, body: body)
  }

  @Test func messagesComeBackInTheOrderTheyWereAddedAcrossConversations() throws {
    let database = try StoreDatabase.inMemory()
    let first = ConversationRecord(id: Fixture.id(10), mentor: mentor, provider: .pi, session: nil)
    let second = ConversationRecord(id: Fixture.id(11), mentor: mentor, provider: .grok, session: "s-2")
    try database.start(first, at: Fixture.instant)
    try database.append(
      [message(30, .prompt(Prompt(text: "Hi", purpose: .chat))), message(20, .reply("Hello"))], to: first.id)
    try database.start(second, at: Fixture.instant)
    let tool = ToolActivity(id: "c1", name: "bash", kind: .execute, subject: "ls", output: "a\n", state: .succeeded)
    try database.append([message(25, .tool(tool)), message(26, .ended(.interrupted))], to: second.id)

    #expect(
      try database.messages(of: mentor).map(\.body) == [
        .prompt(Prompt(text: "Hi", purpose: .chat)), .reply("Hello"), .tool(tool), .ended(.interrupted),
      ])
    #expect(try database.latestConversation(of: mentor) == second)
  }

  @Test func aSessionIsRememberedOnceItStarts() throws {
    let database = try StoreDatabase.inMemory()
    let conversation = ConversationRecord(id: Fixture.id(10), mentor: mentor, provider: .pi, session: nil)
    try database.start(conversation, at: Fixture.instant)

    try database.bind(session: "pi-session", to: conversation.id)

    #expect(try database.latestConversation(of: mentor)?.session == "pi-session")
  }

  @Test func deletingAMentorsConversationsLeavesOthers() throws {
    let database = try StoreDatabase.inMemory()
    let other = Fixture.id(2)
    try database.start(
      ConversationRecord(id: Fixture.id(10), mentor: mentor, provider: .pi, session: nil), at: Fixture.instant)
    try database.start(
      ConversationRecord(id: Fixture.id(12), mentor: other, provider: .pi, session: nil), at: Fixture.instant)
    try database.append([message(30, .reply("mine"))], to: Fixture.id(10))
    try database.append([message(31, .reply("theirs"))], to: Fixture.id(12))

    try database.deleteConversations(of: mentor)

    #expect(try database.messages(of: mentor).isEmpty)
    #expect(try database.latestConversation(of: mentor) == nil)
    #expect(try database.messages(of: other).map(\.body) == [.reply("theirs")])
  }
}
