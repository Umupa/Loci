import Foundation
import Testing

@testable import LociAgents

@Suite(.timeLimit(.minutes(1)))
struct OmpReplayTests {
  private func replay(_ name: String, _ scenario: (Stage) async throws -> Void) async throws {
    let folder = URL(filePath: NSTemporaryDirectory()).appending(path: "loci-omp-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let launcher = try ScriptedLauncher("Omp/\(name)", folder: folder)
    let stage = Stage(
      driver: PiDriver.omp(
        executable: URL(filePath: "/omp"),
        arguments: OmpLiveTests.arguments + ["--session-dir", folder.appending(path: "sessions").path],
        launcher: launcher),
      folder: folder)

    try await scenario(stage)

    launcher.verify()
  }

  @Test func aReplyArrivesAndTheTurnCompletes() async throws { try await replay("reply", Scenario.reply) }
  @Test func aToolCallIsSeenFromStartToResult() async throws { try await replay("tool", Scenario.tool) }
  @Test func anAllowedToolRuns() async throws { try await replay("permission-allow", Scenario.permissionAllowed) }
  @Test func aDeniedToolDoesNotRun() async throws { try await replay("permission-deny", Scenario.permissionDenied) }
  @Test func interruptingStopsTheTurn() async throws { try await replay("interrupt", Scenario.interrupted) }
  @Test func interruptingWithdrawsAnUnansweredRequest() async throws {
    try await replay("interrupt-asking", Scenario.interruptedWhileAsking)
  }
  @Test func aResumedSessionRemembers() async throws { try await replay("resume", Scenario.resumed) }
  @Test func resumingAMissingSessionFails() async throws {
    try await replay("resume-missing") { stage in
      let missing = SessionHandle(provider: .omp, value: Scenario.missingSession.value)
      await #expect(throws: AgentError.sessionNotFound) { _ = try await stage.open(resume: missing) }
    }
  }
  @Test func anUnknownModelFails() async throws { try await replay("bad-model", Scenario.unknownModel) }

  @Test func theReplyArrivesInPieces() async throws {
    try await replay("permission-deny") { stage in
      let session = try await stage.open(.ask)
      let events = await Scenario.watch(try await session.send(Scenario.shellPrompt)) { event in
        if case .permission(let request) = event { await session.answer(request.id, with: .chosen("deny")) }
      }
      #expect(events.filter { if case .text = $0 { true } else { false } }.count > 3)
      await session.close()
    }
  }

  @Test func aPiSessionCannotBeResumedByOmp() async throws {
    let driver = PiDriver.omp(executable: URL(filePath: "/missing-omp"))
    let configuration = SessionConfiguration(
      workingDirectory: URL(filePath: "/tmp"), permission: .full, resume: Scenario.missingSession)
    await #expect(throws: AgentError.sessionNotFound) { _ = try await driver.open(configuration) }
  }

  @Test func anOmpSessionCannotBeResumedByPi() async throws {
    let driver = PiDriver.pi(executable: URL(filePath: "/missing-pi"))
    let configuration = SessionConfiguration(
      workingDirectory: URL(filePath: "/tmp"), permission: .full,
      resume: SessionHandle(provider: .omp, value: "stored-session"))
    await #expect(throws: AgentError.sessionNotFound) { _ = try await driver.open(configuration) }
  }

  @Test func aLocalCommandFinishesWithoutWaitingForAnAgentTurn() async throws {
    try await replay("synthetic-local-command") { stage in
      let session = try await stage.open()
      #expect(session.handle.provider == .omp)
      let events = await Scenario.watch(try await session.send("/local"))
      #expect(events == [.ended(.completed)])
      await session.close()
    }
  }

  @Test func backgroundWorkFinishesBeforeTheTurnEnds() async throws {
    try await replay("synthetic-background") { stage in
      let session = try await stage.open()
      let events = await Scenario.watch(try await session.send("Go on"))
      #expect(events.reply == "First. Background result.")
      #expect(events.endings == [.completed])
      #expect(events.last == .ended(.completed))
      await session.close()
    }
  }

  @Test func aLocalPromptFailureEndsWithTheProvidersError() async throws {
    try await replay("synthetic-local-error") { stage in
      let session = try await stage.open()
      let events = await Scenario.watch(try await session.send("/local"))
      #expect(events.last == .ended(.failed(.provider("Command failed"))))
      await session.close()
    }
  }

  @Test func aWithdrawnDialogClosesWithoutSendingAnAnswer() async throws {
    try await replay("synthetic-dialog-cancel") { stage in
      let session = try await stage.open()
      let events = await Scenario.watch(try await session.send("Go on")) { event in
        if case .permissionClosed(let id) = event { await session.answer(id, with: .chosen("allow")) }
      }
      #expect(events.contains(.permissionClosed(.init("approval"))))
      #expect(events.endings == [.completed])
      await session.close()
    }
  }
}
