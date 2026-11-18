import Foundation
import Testing

@testable import LociAgents

struct CodexTurnStateTests {
  private func json(_ text: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
  }

  @Test func streamedRepliesAreNotRepeatedWhenTheItemCompletes() throws {
    var state = CodexTurnState()
    let delta = try json(#"{"itemId":"a","delta":"pong"}"#)
    #expect(state.receive("item/agentMessage/delta", delta) == [.text("pong")])
    let completed = try json(#"{"item":{"type":"agentMessage","id":"a","text":"pong"}}"#)
    #expect(state.receive("item/completed", completed).isEmpty)
  }

  @Test func aReplyWithoutDeltasStillArrives() throws {
    var state = CodexTurnState()
    let completed = try json(#"{"item":{"type":"agentMessage","id":"a","text":"pong"}}"#)
    #expect(state.receive("item/completed", completed) == [.text("pong")])
    #expect(state.receive("item/completed", completed).isEmpty)
  }

  @Test func toolOutputReplacesThePreviousAggregateAndNonzeroExitFails() throws {
    var state = CodexTurnState()
    let start = try json(#"{"item":{"type":"commandExecution","id":"c","command":"false"}}"#)
    #expect(state.receive("item/started", start).count == 2)
    let first = try json(#"{"itemId":"c","delta":"one"}"#)
    let second = try json(#"{"itemId":"c","delta":"two"}"#)
    #expect(state.receive("item/commandExecution/outputDelta", first) == [.toolCallChanged(.init("c"), .output("one"))])
    #expect(
      state.receive("item/commandExecution/outputDelta", second) == [.toolCallChanged(.init("c"), .output("onetwo"))])
    let end = try json(#"{"item":{"type":"commandExecution","id":"c","exitCode":1,"aggregatedOutput":"onetwo"}}"#)
    #expect(
      state.receive("item/completed", end) == [
        .toolCallChanged(.init("c"), .input(try #require(end["item"]))),
        .toolCallChanged(.init("c"), .finished(output: "onetwo", failed: true)),
      ])
    #expect(state.receive("item/completed", end).isEmpty)
    #expect(state.receive("item/commandExecution/outputDelta", second).isEmpty)
  }

  @Test func distinctNumericAndStringApprovalIdsKeepTheirWireTypes() throws {
    let params = try json(#"{"itemId":"c","command":"touch file"}"#)
    var state = CodexTurnState()
    let numeric = try #require(
      CodexDialog(id: .number(1), method: "item/commandExecution/requestApproval", params: params))
    let string = try #require(CodexDialog(id: .string("1"), method: "item/fileChange/requestApproval", params: params))
    #expect(numeric.request.id != string.request.id)
    _ = state.ask(numeric)
    _ = state.ask(string)
    let reply = state.answer(numeric.request.id, with: .chosen("accept"))
    #expect(reply?["id"] == .number(1))
    #expect(reply?["result"]?["decision"] == .string("accept"))
    #expect(state.answer(numeric.request.id, with: .chosen("accept")) == nil)
    let withdrawn = state.withdraw()
    #expect(withdrawn.count == 1)
    #expect(withdrawn.first?.reply["id"] == .string("1"))
    #expect(withdrawn.first?.reply["result"]?["decision"] == .string("cancel"))
    #expect(withdrawn.first?.event == .permissionClosed(string.request.id))
  }

  @Test func serverResolvedApprovalsAreWithdrawnAndCannotBeAnswered() throws {
    var state = CodexTurnState()
    let dialog = try #require(CodexDialog(id: .number(1), method: "item/fileChange/requestApproval", params: .null))
    _ = state.ask(dialog)
    #expect(
      state.receive("serverRequest/resolved", try json(#"{"requestId":1}"#)) == [.permissionClosed(dialog.request.id)])
    #expect(state.answer(dialog.request.id, with: .chosen("accept")) == nil)
  }

  @Test func permissionGrantsAreLimitedToTheRequestedTurn() throws {
    let params = try json(#"{"permissions":{"network":{"enabled":true},"fileSystem":null}}"#)
    let dialog = try #require(CodexDialog(id: .number(2), method: "item/permissions/requestApproval", params: params))
    #expect(
      dialog.reply(to: .chosen("accept"))["result"]?["permissions"]
        == .object(["network": .object(["enabled": .bool(true)])]))
    #expect(dialog.reply(to: .chosen("accept"))["result"]?["scope"] == .string("turn"))
    #expect(dialog.reply(to: .dismissed)["result"]?["permissions"] == .object([:]))
  }

  @Test func reasoningArrivesSeparatelyFromTheReply() throws {
    var state = CodexTurnState()
    let delta = try json(#"{"itemId":"r","delta":"Thinking"}"#)
    #expect(state.receive("item/reasoning/summaryTextDelta", delta) == [.thinking("Thinking")])
    let completed = try json(#"{"item":{"type":"reasoning","id":"r","summary":["Thinking"]}}"#)
    #expect(state.receive("item/completed", completed).isEmpty)
  }

  @Test func contextUsageDescribesTheLatestTurnRatherThanLifetimeTotals() throws {
    var state = CodexTurnState()
    let usage = try json(
      #"{"tokenUsage":{"last":{"totalTokens":42},"total":{"totalTokens":1000},"modelContextWindow":8000}}"#)
    #expect(state.receive("thread/tokenUsage/updated", usage) == [.context(.init(used: 42, window: 8000))])
  }

  @Test func fileEditsAndMcpResultsKeepTheirToolKindsAndFailures() throws {
    var state = CodexTurnState()
    let file = try json(#"{"item":{"type":"fileChange","id":"f","changes":[],"status":"declined"}}"#)
    let events = state.receive("item/completed", file)
    #expect(events.calls.first?.kind == .edit)
    #expect(events.outputs.first?.failed == true)
    let mcp = try json(
      #"{"item":{"type":"mcpToolCall","id":"m","tool":"lookup","status":"completed","result":{"content":[{"type":"text","text":"Found"}]}}}"#
    )
    let result = state.receive("item/completed", mcp)
    #expect(result.calls.first?.name == "lookup")
    #expect(result.outputs.first?.text == "Found")
    #expect(result.outputs.first?.failed == false)
  }

  @Test func aFileChangeThatOnlyAddsFilesIsACreation() throws {
    var state = CodexTurnState()
    let added = try json(
      #"{"item":{"type":"fileChange","id":"f","changes":[{"path":"/w/cleanup.py","kind":{"type":"add"}}]}}"#)
    let updated = try json(
      #"{"item":{"type":"fileChange","id":"g","changes":[{"path":"/w/cleanup.py","kind":{"type":"update"}}]}}"#)

    #expect(state.receive("item/started", added).calls.first?.kind == .create)
    #expect(state.receive("item/started", updated).calls.first?.kind == .edit)
  }

  @Test func aWebSearchTellsItsQueryWhenItCompletes() throws {
    var state = CodexTurnState()
    _ = state.receive("item/started", try json(#"{"item":{"type":"webSearch","id":"w","query":""}}"#))
    let done = try json(#"{"item":{"type":"webSearch","id":"w","query":"python str.strip"}}"#)

    #expect(state.receive("item/completed", done).changes.contains(.input(try #require(done["item"]))))
  }
}
