import LociAgents
import LociModel
import Testing

@testable import LociHost

struct TurnRecordTests {
  private let at = TestWorld.instant

  private func record(_ world: TestWorld) -> TurnRecord {
    TurnRecord(prompt: Prompt(text: "Hi", purpose: .chat), at: at, newID: { world.nextID() })
  }

  @Test func streamedChunksKeepTheMessageIdentityAndStartTime() throws {
    var turn = record(TestWorld())
    turn.apply(.text("Hello"), at: at)
    let first = try #require(turn.messages.last)
    turn.apply(.text(" there"), at: Timestamp(millisecondsSince1970: at.millisecondsSince1970 + 1))
    #expect(turn.messages.last == Message(id: first.id, at: first.at, body: .reply("Hello there")))
    #expect(turn.live.startedAt == at)
  }

  @Test func thinkingAndRepliesStayInOrderInsteadOfMergingAcrossOtherMessages() {
    var turn = record(TestWorld())
    for event in [
      AgentEvent.thinking("First"), .thinking(" think"), .text("Answer"), .notice(.message("retry")), .text("More"),
      .ended(.completed),
    ] {
      turn.apply(event, at: at)
    }
    #expect(
      turn.messages.dropFirst().map(\.body) == [
        .thinking("First think"), .reply("Answer"), .notice("retry"), .reply("More"),
      ])
  }

  @Test func toolUpdatesChangeOnlyTheirOwnCallAndPreserveIdentity() throws {
    var turn = record(TestWorld())
    turn.apply(
      .toolCall(ToolCall(id: .init("a"), name: "read", kind: .read, input: .object(["path": .string("a.md")]))), at: at)
    let first = try #require(turn.messages.last)
    turn.apply(.toolCall(ToolCall(id: .init("b"), name: "bash", kind: .execute, input: .object([:]))), at: at)
    turn.apply(.toolCallChanged(.init("a"), .input(.object(["file_path": .string("b.md")]))), at: at)
    turn.apply(.toolCallChanged(.init("a"), .output("partial")), at: at)
    turn.apply(.toolCallChanged(.init("a"), .finished(output: "final", failed: true)), at: at)
    turn.apply(.toolCallChanged(.init("unknown"), .output("ignored")), at: at)
    #expect(
      turn.messages[1]
        == Message(
          id: first.id, at: first.at,
          body: .tool(
            ToolActivity(id: "a", name: "read", kind: .read, subject: "b.md", output: "final", state: .failed))))
    #expect(turn.messages.count == 3)
    #expect(turn.live.latestTool?.id == "b")
  }

  @Test func aWithdrawnPermissionCannotBeAnsweredAgain() {
    var turn = record(TestWorld())
    turn.apply(
      .permission(PermissionRequest(id: .init("ask"), title: "bash", options: [.init(id: "deny", role: .deny)])), at: at
    )
    #expect(turn.live.waiting.count == 1)
    turn.apply(.permissionClosed(.init("ask")), at: at)
    #expect(turn.live.waiting.isEmpty)
    let answered = turn.answer("ask", .chosen("deny"))
    let unknown = turn.answer("missing", .dismissed)
    #expect(!answered)
    #expect(!unknown)
    #expect(
      turn.messages.last?.body
        == .permission(
          PermissionAsk(
            id: "ask", title: "bash", tool: nil, options: [.init(id: "deny", role: .deny, label: nil)],
            answer: .dismissed)))
  }
}
