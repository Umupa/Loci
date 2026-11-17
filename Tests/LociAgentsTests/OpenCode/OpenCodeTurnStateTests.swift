import Foundation
import Testing

@testable import LociAgents

struct OpenCodeTurnStateTests {
  private func value(_ json: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
  }

  @Test func replyAndReasoningChunksStaySeparate() throws {
    var state = OpenCodeTurnState()
    #expect(
      state.receive(try value(#"{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"Hello"}}"#))
        == [.text("Hello")])
    #expect(
      state.receive(try value(#"{"sessionUpdate":"agent_thought_chunk","content":{"type":"text","text":"Think"}}"#))
        == [.thinking("Think")])
    #expect(
      state.receive(try value(#"{"sessionUpdate":"user_message_chunk","content":{"type":"text","text":"Private"}}"#))
        .isEmpty)
  }

  @Test func aToolIsAnnouncedOnceAndKeepsItsLatestOutput() throws {
    var state = OpenCodeTurnState()
    let pending = try value(
      #"{"sessionUpdate":"tool_call","toolCallId":"c1","title":"Read notes.txt","kind":"read","status":"pending","rawInput":{}}"#
    )
    let running = try value(
      #"{"sessionUpdate":"tool_call_update","toolCallId":"c1","status":"in_progress","rawInput":{"filePath":"notes.txt"}}"#
    )
    let output = try value(
      #"{"sessionUpdate":"tool_call_update","toolCallId":"c1","content":[{"type":"content","content":{"type":"text","text":"marmalade"}}]}"#
    )
    let finished = try value(#"{"sessionUpdate":"tool_call_update","toolCallId":"c1","status":"completed"}"#)
    let call = ToolCall(id: .init("c1"), name: "Read notes.txt", kind: .read, input: .object([:]))
    #expect(state.receive(pending) == [.toolCall(call)])
    #expect(state.receive(pending).isEmpty)
    #expect(
      state.receive(running) == [
        .toolCallChanged(call.id, .input(.object(["filePath": .string("notes.txt")]))),
        .toolCallChanged(call.id, .running),
      ])
    #expect(state.receive(output) == [.toolCallChanged(call.id, .output("marmalade"))])
    #expect(state.receive(finished) == [.toolCallChanged(call.id, .finished(output: "marmalade", failed: false))])
    #expect(state.receive(output).isEmpty)
    #expect(state.receive(finished).isEmpty)
  }

  @Test func failedToolsExposeTheProvidersError() throws {
    var state = OpenCodeTurnState()
    _ = state.receive(try value(#"{"sessionUpdate":"tool_call","toolCallId":"c1","title":"bash","kind":"execute"}"#))
    let events = state.receive(
      try value(
        #"{"sessionUpdate":"tool_call_update","toolCallId":"c1","status":"failed","content":[{"type":"content","content":{"type":"text","text":"Rejected"}}]}"#
      ))
    #expect(events == [.toolCallChanged(.init("c1"), .finished(output: "Rejected", failed: true))])
  }

  @Test func usageAndCompactionAreReportedWithoutInventingContextCounts() throws {
    var state = OpenCodeTurnState()
    #expect(
      state.receive(try value(#"{"sessionUpdate":"usage_update","used":42,"size":1000}"#)) == [
        .context(.init(used: 42, window: 1000))
      ])
    #expect(
      state.receive(
        try value(#"{"sessionUpdate":"session_info_update","_meta":{"opencode/compaction":{"status":"started"}}}"#))
        == [.notice(.compacting)])
    #expect(state.receive(try value(#"{"sessionUpdate":"future_update"}"#)).isEmpty)
  }

  @Test func permissionRepliesPreserveOptionIdentifiersAndCancelInvalidAnswers() throws {
    let params = try value(
      #"{"sessionId":"s1","toolCall":{"toolCallId":"c1","title":"Run bash"},"options":[{"optionId":"once","kind":"allow_once","name":"Allow once"},{"optionId":"always","kind":"allow_always","name":"Always allow"},{"optionId":"reject","kind":"reject_once","name":"Reject"}]}"#
    )
    let dialog = try #require(OpenCodeDialog(id: .number(7), params: params))
    #expect(dialog.request.id == .init("7"))
    #expect(dialog.request.toolCall == .init("c1"))
    #expect(dialog.request.options.map(\.role) == [.allow, .allowAlways, .deny])
    let selected = try value(#"{"outcome":{"outcome":"selected","optionId":"always"}}"#)
    let cancelled = try value(#"{"outcome":{"outcome":"cancelled"}}"#)
    #expect(dialog.reply(to: .chosen("always")) == selected)
    #expect(dialog.reply(to: .chosen("unknown")) == cancelled)
    #expect(dialog.reply(to: .dismissed) == cancelled)
  }
}
