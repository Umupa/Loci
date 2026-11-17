import Foundation
import Testing

@testable import LociAgents

@Suite(.timeLimit(.minutes(1)))
struct AntigravityReplayTests {
  private func replay(_ name: String, _ scenario: (Stage) async throws -> Void) async throws {
    let folder = URL(filePath: NSTemporaryDirectory()).appending(path: "loci-antigravity-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let launcher = try ScriptedLauncher("Antigravity/\(name)", folder: folder)
    let stage = Stage(
      driver: AcpDriver.antigravity(
        executable: URL(filePath: "/server/agy_acp_server.par"), environment: ["LOCI_TEST": "antigravity"],
        launcher: LaunchCheck(replay: launcher)),
      folder: folder)
    try await scenario(stage)
    launcher.verify()
  }

  @Test func aReplyArrivesAndTheTurnCompletes() async throws { try await replay("reply", Scenario.reply) }
  @Test func aToolCallIsSeenFromStartToResult() async throws { try await replay("tool", AntigravityScenario.tool) }
  @Test func anAllowedToolRuns() async throws {
    try await replay("permission-allow", AntigravityScenario.permissionAllowed)
  }
  @Test func aDeniedToolDoesNotRun() async throws {
    try await replay("permission-deny", AntigravityScenario.permissionDenied)
  }
  @Test func interruptingStopsTheTurn() async throws { try await replay("interrupt", Scenario.interrupted) }
  @Test func interruptingWithdrawsAnUnansweredRequest() async throws {
    try await replay("interrupt-asking", AntigravityScenario.interruptedWhileAsking)
  }
  @Test func aResumedSessionRemembers() async throws { try await replay("resume", Scenario.resumed) }
  @Test func resumingAMissingSessionFails() async throws {
    try await replay("resume-missing", AntigravityScenario.resumedMissing)
  }
  @Test func anUnknownModelFails() async throws { try await replay("bad-model", AntigravityScenario.unknownModel) }

  @Test func aRefusedPermissionModeClosesTheProgramBeforeAnyPrompt() async throws {
    try await replay("synthetic-mode-refused") { stage in
      await #expect(throws: AgentError.rejected("Internal error: Mode change refused")) { _ = try await stage.open() }
    }
  }

  @Test func aSelectedModelUsesTheAdvertisedConfigurationOption() async throws {
    try await replay("synthetic-selected-model") { stage in
      let session = try await stage.open(model: "gemini-3.8-flash-low")
      await session.close()
    }
  }

  @Test func aTruncatedReplyFailsInsteadOfReportingCompletion() async throws {
    try await replay("synthetic-truncated") { stage in
      let session = try await stage.open()
      let events = await Scenario.watch(try await session.send("Reply with exactly one word: pong"))
      #expect(events.endings == [.failed(.provider("The agent ended the turn (max_tokens)."))])
      await session.close()
    }
  }

  @Test func aReplyIsDeliveredInSeveralPieces() async throws {
    try await replay("permission-deny") { stage in
      let session = try await stage.open(.ask)
      let events = await Scenario.watch(try await session.send(AntigravityScenario.shellPrompt)) { event in
        guard case .permission(let request) = event else { return }
        await session.answer(request.id, with: .chosen(request.options.first { $0.role == .deny }?.id ?? ""))
      }
      #expect(events.filter { if case .text = $0 { true } else { false } }.count > 3)
      #expect(events.last == .ended(.completed))
      await session.close()
    }
  }

  @Test func aHandleFromAnotherProviderIsRejectedBeforeLaunching() async {
    let driver = AcpDriver.antigravity(executable: URL(filePath: "/not-installed"))
    let configuration = SessionConfiguration(
      workingDirectory: URL(filePath: "/tmp"), permission: .ask,
      resume: SessionHandle(provider: .pi, value: "other-session"))
    await #expect(throws: AgentError.sessionNotFound) { _ = try await driver.open(configuration) }
  }

  @Test func aCapacityErrorSentAsReplyTextFailsTheTurn() async throws {
    try await replay("capacity-error") { stage in
      let session = try await stage.open(.ask)
      let events = await Scenario.watch(try await session.send(AntigravityScenario.shellPrompt))
      #expect(events.endings == [.failed(.provider("No capacity available for model some-model on the server"))])
      await session.close()
    }
  }
}

private struct LaunchCheck: ProgramLauncher {
  let replay: ScriptedLauncher

  func launch(_ invocation: Invocation) throws(AgentError) -> RunningProgram {
    #expect(invocation.executable == URL(filePath: "/server/agy_acp_server.par"))
    #expect(invocation.workingDirectory.path == "/server")
    #expect(invocation.arguments == [])
    #expect(invocation.environment == ["LOCI_TEST": "antigravity"])
    return try replay.launch(invocation)
  }
}
