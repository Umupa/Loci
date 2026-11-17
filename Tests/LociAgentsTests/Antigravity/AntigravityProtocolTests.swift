import Foundation
import Testing

@testable import LociAgents

struct AntigravityProtocolTests {
  @Test func aCommandResultKeepsTheOutputReportedOutsideContentBlocks() throws {
    var state = AcpTurnState()
    let params = try JSONDecoder().decode(
      JSONValue.self,
      from: Data(
        #"{"update":{"sessionUpdate":"tool_call_update","toolCallId":"command-1","status":"completed","rawOutput":{"combinedOutput":"loci-42\n","exitCode":0}}}"#
          .utf8))
    #expect(
      state.receive(params).contains(
        .toolCallChanged(.init("command-1"), .finished(output: "loci-42\n", failed: false))))
  }

  @Test func contextUsageIncludesTheWindowReportedByTheServer() throws {
    var state = AcpTurnState()
    let params = try JSONDecoder().decode(
      JSONValue.self, from: Data(#"{"update":{"sessionUpdate":"usage_update","used":23,"size":1048576}}"#.utf8))
    #expect(state.receive(params) == [.context(ContextUsage(used: 23, window: 1_048_576))])
  }

  @Test func clarificationOptionsRemainHumanChoicesEvenWhenTheirKindSaysAllow() throws {
    var state = AcpTurnState()
    let params = try JSONDecoder().decode(
      JSONValue.self,
      from: Data(
        #"{"toolCall":{"toolCallId":"interaction_goal","title":"Which goal?"},"options":[{"optionId":"kernel","kind":"allow_once","name":"Kernel"}]}"#
          .utf8))
    let event = state.ask(id: .number(7), params)
    guard case .permission(let request) = event else {
      Issue.record("Expected a question")
      return
    }
    #expect(request.options == [.init(id: "kernel", role: .choice, label: "Kernel")])
    #expect(state.answer(request.id, with: .chosen("kernel"))?.1 == AcpTurnState.selected("kernel"))
  }

  @Test func providerFailuresKeepTheDetailHiddenByTheGenericRPCMessage() {
    let line = Data(
      #"{"jsonrpc":"2.0","id":1,"error":{"code":-32603,"message":"Internal error","data":{"details":"Quota exhausted"}}}"#
        .utf8)
    #expect(AcpRecord(line: line) == .response(id: 1, outcome: .failure(.rejected("Internal error: Quota exhausted"))))
  }
}
