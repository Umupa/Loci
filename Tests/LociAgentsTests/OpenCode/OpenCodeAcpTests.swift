import Foundation
import Testing

@testable import LociAgents

struct OpenCodeAcpTests {
  private func value(_ json: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
  }

  private func update(_ json: String) throws -> JSONValue {
    .object(["sessionId": .string("s1"), "update": try value(json)])
  }

  @Test func replyAndReasoningChunksStaySeparate() throws {
    var state = AcpTurnState()
    #expect(
      state.receive(try update(#"{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"Hello"}}"#))
        == [.text("Hello")])
    #expect(
      state.receive(try update(#"{"sessionUpdate":"agent_thought_chunk","content":{"type":"text","text":"Think"}}"#))
        == [.thinking("Think")])
    #expect(
      state.receive(try update(#"{"sessionUpdate":"user_message_chunk","content":{"type":"text","text":"Private"}}"#))
        .isEmpty)
  }

  @Test func aToolIsAnnouncedOnceAndKeepsItsLatestOutput() throws {
    var state = AcpTurnState()
    let pending = try update(
      #"{"sessionUpdate":"tool_call","toolCallId":"c1","title":"Read notes.txt","kind":"read","status":"pending","rawInput":{}}"#
    )
    let running = try update(
      #"{"sessionUpdate":"tool_call_update","toolCallId":"c1","status":"in_progress","rawInput":{"filePath":"notes.txt"}}"#
    )
    let output = try update(
      #"{"sessionUpdate":"tool_call_update","toolCallId":"c1","content":[{"type":"content","content":{"type":"text","text":"marmalade"}}]}"#
    )
    let finished = try update(#"{"sessionUpdate":"tool_call_update","toolCallId":"c1","status":"completed"}"#)
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
    var state = AcpTurnState()
    _ = state.receive(try update(#"{"sessionUpdate":"tool_call","toolCallId":"c1","title":"bash","kind":"execute"}"#))
    let events = state.receive(
      try update(
        #"{"sessionUpdate":"tool_call_update","toolCallId":"c1","status":"failed","content":[{"type":"content","content":{"type":"text","text":"Rejected"}}]}"#
      ))
    #expect(events == [.toolCallChanged(.init("c1"), .finished(output: "Rejected", failed: true))])
  }

  @Test func usageAndCompactionAreReportedWithoutInventingContextCounts() throws {
    var state = AcpTurnState()
    #expect(
      state.receive(try update(#"{"sessionUpdate":"usage_update","used":42,"size":1000}"#)) == [
        .context(.init(used: 42, window: 1000))
      ])
    #expect(
      state.receive(
        try update(#"{"sessionUpdate":"session_info_update","_meta":{"opencode/compaction":{"status":"started"}}}"#))
        == [.notice(.compacting)])
    #expect(state.receive(try update(#"{"sessionUpdate":"future_update"}"#)).isEmpty)
  }

  @Test func permissionRepliesPreserveOptionIdentifiersAndCancelInvalidAnswers() throws {
    let params = try value(
      #"{"sessionId":"s1","toolCall":{"toolCallId":"c1","title":"Run bash"},"options":[{"optionId":"once","kind":"allow_once","name":"Allow once"},{"optionId":"always","kind":"allow_always","name":"Always allow"},{"optionId":"reject","kind":"reject_once","name":"Reject"}]}"#
    )
    var state = AcpTurnState()
    let event = state.ask(id: .number(7), params)
    guard case .permission(let request) = event else {
      Issue.record("A permission request is expected")
      return
    }
    #expect(request.id == .init("7"))
    #expect(request.toolCall == .init("c1"))
    #expect(request.options.map(\.role) == [.allow, .allowAlways, .deny])
    let selected = try value(#"{"outcome":{"outcome":"selected","optionId":"always"}}"#)
    #expect(state.answer(request.id, with: .chosen("always"))?.1 == selected)
    _ = state.ask(id: .number(7), params)
    #expect(state.answer(request.id, with: .chosen("unknown"))?.1 == AcpTurnState.cancelled)
    _ = state.ask(id: .number(7), params)
    #expect(state.answer(request.id, with: .dismissed)?.1 == AcpTurnState.cancelled)
  }
}
