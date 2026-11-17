import Foundation
import Testing

@testable import LociAgents

/// The scenarios against recordings of the real Grok, made by `GrokLiveTests`.
@Suite(.timeLimit(.minutes(1)))
struct GrokReplayTests {
  private func replay(_ name: String, _ scenario: (Stage) async throws -> Void) async throws {
    let folder = URL(filePath: NSTemporaryDirectory()).appending(path: "loci-grok-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let launcher = try ScriptedLauncher("grok-\(name)", folder: folder)
    let stage = Stage(driver: AcpDriver.grok(executable: URL(filePath: "/grok"), launcher: launcher), folder: folder)

    try await scenario(stage)

    launcher.verify()
  }

  @Test func aReplyArrivesAndTheTurnCompletes() async throws { try await replay("reply", Scenario.reply) }
  @Test func aToolCallIsSeenFromStartToResult() async throws { try await replay("tool", GrokScenario.tool) }
  @Test func anAllowedToolRuns() async throws { try await replay("permission-allow", GrokScenario.permissionAllowed) }
  @Test func aDeniedToolDoesNotRun() async throws {
    try await replay("permission-deny", GrokScenario.permissionDenied)
  }
  @Test func interruptingStopsTheTurn() async throws { try await replay("interrupt", Scenario.interrupted) }
  @Test func interruptingWithdrawsAnUnansweredRequest() async throws {
    try await replay("interrupt-asking", Scenario.interruptedWhileAsking)
  }
  @Test func aResumedSessionRemembers() async throws { try await replay("resume", Scenario.resumed) }
  @Test func resumingAMissingSessionFails() async throws {
    try await replay("resume-missing", GrokScenario.resumedMissing)
  }

  @Test func theAgentsOwnRequestsForFilesAreRefused() async throws {
    var state = AcpTurnState()
    let event = state.ask(
      id: .number(7),
      .object([
        "toolCall": .object(["toolCallId": .string("call-1"), "title": .string("Execute `ls`")]),
        "options": .array([
          .object(["optionId": .string("allow-once"), "kind": .string("allow_once"), "name": .string("Yes")]),
          .object(["optionId": .string("reject-once"), "kind": .string("reject_once")]),
        ]),
      ]))
    #expect(
      event
        == .permission(
          PermissionRequest(
            id: .init("7"), title: "Execute `ls`", toolCall: .init("call-1"),
            options: [.init(id: "allow-once", role: .allow, label: "Yes"), .init(id: "reject-once", role: .deny)])))
    let unknown = state.answer(.init("7"), with: .chosen("made-up"))
    #expect(unknown?.1 == AcpTurnState.cancelled)
    #expect(state.answer(.init("7"), with: .chosen("allow-once")) == nil)
  }
}
