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
      state.receive("item/completed", end) == [.toolCallChanged(.init("c"), .finished(output: "onetwo", failed: true))])
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
}
