import Foundation
import Testing

@testable import LociAgents

struct PiTurnStateTests {
  private func record(_ json: String) -> PiRecord? {
    PiRecord(line: Data(json.utf8))
  }

  private func events(_ lines: [String]) -> (events: [AgentEvent], end: TurnEnd) {
    var state = PiTurnState()
    var seen: [AgentEvent] = []
    for line in lines {
      if case .event(let event) = record(line) { seen += state.receive(event) }
    }
    return (seen, state.end(interrupted: false))
  }

  private let failed =
    #"{"type":"message_end","message":{"role":"assistant","stopReason":"error","errorMessage":"529 overloaded"}}"#

  @Test func aFailedReplyFailsTheTurnWithTheProvidersWords() {
    let turn = events([failed, #"{"type":"agent_end","willRetry":false}"#])
    #expect(turn.end == .failed(.provider("529 overloaded")))
  }

  @Test func aFailureThatPiRetriesIsNotReported() {
    let turn = events([
      failed, #"{"type":"agent_end","willRetry":true}"#,
      #"{"type":"auto_retry_start","attempt":1,"maxAttempts":3,"delayMs":2000}"#,
      #"{"type":"message_update","assistantMessageEvent":{"type":"text_delta","contentIndex":0,"delta":"Hi"}}"#,
      #"{"type":"agent_end","willRetry":false}"#,
    ])
    #expect(turn.events == [.notice(.retrying(attempt: 1, of: 3)), .text("Hi")])
    #expect(turn.end == .completed)
  }

  @Test func anInterruptedTurnIsNotAFailure() {
    var state = PiTurnState()
    if case .event(let event) = record(failed) { _ = state.receive(event) }
    #expect(state.end(interrupted: true) == .interrupted)
  }

  @Test func outputArrivingAfterAToolFinishedIsDropped() {
    let turn = events([
      #"{"type":"tool_execution_start","toolCallId":"c1","toolName":"bash","args":{"command":"ls"}}"#,
      #"{"type":"tool_execution_end","toolCallId":"c1","toolName":"bash","result":{"content":[{"type":"text","text":"a"}]},"isError":false}"#,
      #"{"type":"tool_execution_update","toolCallId":"c1","toolName":"bash","partialResult":{"content":[{"type":"text","text":"late"}]}}"#,
      #"{"type":"tool_execution_end","toolCallId":"c1","toolName":"bash","result":{"content":[]},"isError":true}"#,
    ])
    let call = ToolCall(id: .init("c1"), name: "bash", kind: .execute, input: .object(["command": .string("ls")]))
    #expect(
      turn.events == [
        .toolCall(call), .toolCallChanged(call.id, .running),
        .toolCallChanged(call.id, .finished(output: "a", failed: false)),
      ])
  }

  @Test func aToolCallIsAnnouncedOnceAndItsArgumentsFollow() {
    let turn = events([
      #"{"type":"message_update","assistantMessageEvent":{"type":"toolcall_start","contentIndex":0,"id":"c1","toolName":"write"}}"#,
      #"{"type":"message_update","assistantMessageEvent":{"type":"toolcall_delta","contentIndex":0,"delta":"{\"pa"}}"#,
      #"{"type":"message_update","assistantMessageEvent":{"type":"toolcall_end","contentIndex":0,"toolCall":{"id":"c1","name":"write","arguments":{"path":"a.md"}}}}"#,
      #"{"type":"tool_execution_start","toolCallId":"c1","toolName":"write","args":{"path":"a.md"}}"#,
      #"{"type":"tool_execution_update","toolCallId":"c1","toolName":"write","partialResult":{"content":[{"type":"text","text":"wri"}]}}"#,
    ])
    let id = ToolCall.ID("c1")
    #expect(
      turn.events == [
        .toolCall(ToolCall(id: id, name: "write", kind: .edit, input: .object([:]))),
        .toolCallChanged(id, .input(.object(["path": .string("a.md")]))), .toolCallChanged(id, .running),
        .toolCallChanged(id, .output("wri")),
      ])
  }

  @Test func compactionAndExtensionErrorsAreNotices() {
    let turn = events([
      #"{"type":"compaction_start","reason":"threshold"}"#,
      #"{"type":"extension_error","extensionPath":"/x.ts","event":"tool_call","error":"boom"}"#,
      #"{"type":"some_future_event"}"#,
    ])
    #expect(turn.events == [.notice(.compacting), .notice(.message("boom"))])
  }

  @Test func aLineThatIsNotARecordIsSkipped() {
    #expect(record("not json") == nil)
    #expect(record("[1,2]") == nil)
    #expect(record(#"{"type":"extension_ui_request","id":"w","method":"setWidget","widgetLines":["x"]}"#) == nil)
  }
}

struct PiDialogTests {
  @Test func aConfirmFromAnotherExtensionShowsItsOwnWordsWithoutTerminalCodes() {
    let dialog = PiDialog(
      id: "d", kind: .confirm, title: "\u{1B}[31mDelete?\u{1B}[0m", message: "This cannot be undone")
    #expect(dialog.request.title == "Delete? — This cannot be undone")
    #expect(dialog.request.toolCall == nil)
    #expect(dialog.request.options.map(\.role) == [.allow, .deny])
  }

  @Test func eachAnswerBecomesTheReplyPiExpects() {
    let confirm = PiDialog(id: "d", kind: .confirm, title: "Go?", message: "")
    let select = PiDialog(id: "s", kind: .select(["a", "b"]), title: "Which?", message: "")
    #expect(confirm.reply(to: .chosen("allow")) == .reply(dialog: "d", .confirmed(true)))
    #expect(confirm.reply(to: .chosen("deny")) == .reply(dialog: "d", .confirmed(false)))
    #expect(confirm.reply(to: .dismissed) == .reply(dialog: "d", .cancelled))
    #expect(confirm.reply(to: .chosen("nonsense")) == .reply(dialog: "d", .cancelled))
    #expect(select.reply(to: .chosen("1")) == .reply(dialog: "s", .value("b")))
    #expect(select.reply(to: .chosen("7")) == .reply(dialog: "s", .cancelled))
  }

  @Test func theBundledExtensionIsThere() throws {
    let gate = try #require(PiDriver.askBeforeTools)
    #expect(try String(contentsOf: gate, encoding: .utf8).contains(PiDialog.ownTitle))
  }
}
