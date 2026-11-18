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

  @Test func theAnswerIsTheRepliesOfATurnThatEndedAsItShould() {
    var turn = record(TestWorld())
    turn.apply(.text("First part."), at: at)
    turn.apply(.toolCall(ToolCall(id: .init("t"), name: "read", kind: .read, input: .object([:]))), at: at)
    turn.apply(.text(" Second part. "), at: at)
    #expect(turn.answer == "First part.\n\nSecond part.")

    turn.apply(.ended(.interrupted), at: at)
    #expect(turn.answer == nil)
  }

  @Test func aTurnWithoutAReplyHasNoAnswer() {
    var turn = record(TestWorld())
    turn.apply(.thinking("Hmm"), at: at)
    #expect(turn.answer == nil)
  }

  @Test func aCommandThatReadsAFileIsAboutThatFile() {
    let action: JSONValue = .object([
      "type": .string("read"), "name": .string("cleanup.py"), "path": .string("/w/cleanup.py"),
    ])
    let read: JSONValue = .object([
      "command": .string("/bin/zsh -lc 'cat cleanup.py'"), "commandActions": .array([action]),
    ])
    #expect(TurnRecord.subject(of: read) == "/w/cleanup.py")
  }

  @Test func aFileChangeIsAboutTheFileItChanges() {
    let added: JSONValue = .object(["path": .string("/w/cleanup.py"), "kind": .object(["type": .string("add")])])
    let change: JSONValue = .object(["changes": .array([added])])
    #expect(TurnRecord.subject(of: change) == "/w/cleanup.py")
  }
}
