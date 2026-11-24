import Foundation
import LociModel
import Testing

@testable import LociAgents

struct ClaudeCodeTurnStateTests {
  private func record(_ text: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
  }

  @Test func streamingTextAndThinkingAreNotRepeatedByTheFinalMessage() throws {
    var state = ClaudeCodeTurnState()
    let records = [
      #"{"type":"stream_event","event":{"type":"message_start"}}"#,
      #"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"Let me think"}}}"#,
      #"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"po"}}}"#,
      #"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"ng"}}}"#,
      #"{"type":"assistant","message":{"content":[{"type":"thinking","thinking":"Let me think"},{"type":"text","text":"pong"}]}}"#,
    ]
    let events = try records.flatMap { state.receive(try record($0)) }
    #expect(events == [.thinking("Let me think"), .text("po"), .text("ng")])
  }

  @Test func aNonstreamedReplyStillArrives() throws {
    var state = ClaudeCodeTurnState()
    let events = state.receive(
      try record(#"{"type":"assistant","message":{"content":[{"type":"text","text":"pong"}]}}"#))
    #expect(events == [.text("pong")])
  }

  @Test func toolArgumentsAreCompletedAndResultsAreDeliveredOnce() throws {
    var state = ClaudeCodeTurnState()
    let start = try record(
      #"{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"call","name":"Bash","input":{}}}}"#
    )
    let delta = try record(
      #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"command\":\"pwd\"}"}}}"#
    )
    let stop = try record(#"{"type":"stream_event","event":{"type":"content_block_stop","index":0}}"#)
    let snapshot = try record(
      #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"call","name":"Bash","input":{"command":"pwd"}}]}}"#
    )
    let result = try record(
      #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"call","content":[{"type":"text","text":"/tmp"}]}]}}"#
    )
    let events = [start, delta, stop, snapshot, result, result].flatMap { state.receive($0) }
    #expect(events.calls.count == 1)
    #expect(events.calls.first?.kind == .execute)
    #expect(
      events.changes == [
        .input(.object(["command": .string("pwd")])), .finished(output: "/tmp", failed: false),
      ])
  }

  @Test func aToolAwaitingPermissionIsNotReportedAsRunning() throws {
    var state = ClaudeCodeTurnState()
    let snapshot = try record(
      #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"call","name":"Bash","input":{"command":"pwd"}}]}}"#
    )
    let announced = state.receive(snapshot)
    #expect(announced.calls.count == 1)
    #expect(!announced.changes.contains(.running))
    let progress = try record(#"{"type":"tool_progress","tool_use_id":"call"}"#)
    #expect(state.receive(progress) == [.toolCallChanged(.init("call"), .running)])
    #expect(state.receive(progress).isEmpty)
  }

  @Test func aHeartbeatMarksItsParentToolAsRunning() throws {
    var state = ClaudeCodeTurnState()
    _ = state.receive(
      try record(
        #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"call","name":"Bash","input":{}}]}}"#))
    let heartbeat = try record(
      #"{"type":"tool_progress","heartbeat":true,"tool_use_id":"call-heartbeat-0","parent_tool_use_id":"call","elapsed_time_seconds":30}"#
    )
    #expect(state.receive(heartbeat) == [.toolCallChanged(.init("call"), .running)])
    #expect(state.receive(heartbeat).isEmpty)
  }

  @Test func aFinishedToolCannotStartRunningAgain() throws {
    var state = ClaudeCodeTurnState()
    _ = state.receive(
      try record(
        #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"call","name":"Bash","input":{}}]}}"#))
    _ = state.receive(
      try record(
        #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"call","content":"done"}]}}"#))
    let progress = try record(#"{"type":"tool_progress","tool_use_id":"call"}"#)
    #expect(state.receive(progress).isEmpty)
  }

  @Test func subagentTextDoesNotEnterTheParentReply() throws {
    var state = ClaudeCodeTurnState()
    let event = try record(
      #"{"type":"stream_event","parent_tool_use_id":"child","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"private"}}}"#
    )
    #expect(state.receive(event).isEmpty)
  }

  @Test func anErrorResultNeverLooksLikeSuccess() throws {
    let state = ClaudeCodeTurnState()
    let result = try record(#"{"type":"result","subtype":"success","is_error":true,"result":"API Error: quota"}"#)
    #expect(state.end(result, interrupted: false) == .failed(.provider("API Error: quota")))
    #expect(state.end(result, interrupted: true) == .interrupted)
  }

  @Test func contextUsesTheLatestRequestRatherThanAccumulatedBilling() throws {
    var state = ClaudeCodeTurnState()
    let start = try record(
      #"{"type":"stream_event","event":{"type":"message_start","message":{"usage":{"input_tokens":5,"cache_read_input_tokens":10,"cache_creation_input_tokens":20}}}}"#
    )
    _ = state.receive(start)
    let result = try record(#"{"type":"result","modelUsage":{"haiku":{"inputTokens":200,"contextWindow":200000}}}"#)
    #expect(state.receive(result) == [.context(.init(used: 35, window: 200000))])
  }

  @Test func contextIncludesTheLatestRepliesOutputTokens() throws {
    var state = ClaudeCodeTurnState()
    let message = try record(
      #"{"type":"assistant","message":{"content":[],"usage":{"input_tokens":2,"cache_read_input_tokens":10,"cache_creation_input_tokens":20,"output_tokens":4}}}"#
    )
    _ = state.receive(message)
    let result = try record(#"{"type":"result","modelUsage":{"haiku":{"inputTokens":200,"contextWindow":200000}}}"#)
    #expect(state.receive(result) == [.context(.init(used: 36, window: 200000))])
  }

  @Test func cancellingAPermissionWithdrawsItAndLateAnswersAreIgnored() throws {
    var state = ClaudeCodeTurnState()
    let value = try record(
      #"{"type":"control_request","request_id":"r","request":{"subtype":"can_use_tool","tool_name":"Bash","tool_use_id":"call","input":{"command":"pwd"}}}"#
    )
    let dialog = try #require(ClaudeCodeDialog(value))
    #expect(state.ask(dialog) == .permission(dialog.request))
    #expect(state.ask(dialog) == nil)
    #expect(
      state.receive(try record(#"{"type":"control_cancel_request","request_id":"r"}"#)) == [
        .permissionClosed(.init("r"))
      ])
    #expect(state.answer(.init("r"), with: .chosen("allow")) == nil)
    #expect(state.withdraw().isEmpty)
  }

  @Test func dismissedOrInvalidPermissionsAreDeniedAndAllowKeepsTheInput() throws {
    let value = try record(
      #"{"type":"control_request","request_id":"r","request":{"subtype":"can_use_tool","tool_name":"Bash","input":{"command":"pwd"}}}"#
    )
    let dialog = try #require(ClaudeCodeDialog(value))
    let allowed = dialog.reply(to: .chosen("allow")).record(id: "")
    #expect(allowed["response"]?["response"]?["updatedInput"] == dialog.input)
    for answer in [PermissionAnswer.dismissed, .chosen("unknown"), .chosen("deny")] {
      #expect(dialog.reply(to: answer).record(id: "")["response"]?["response"]?["behavior"]?.string == "deny")
    }
  }
}
