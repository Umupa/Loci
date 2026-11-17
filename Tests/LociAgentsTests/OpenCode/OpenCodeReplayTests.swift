import Foundation
import Testing

@testable import LociAgents

@Suite(.timeLimit(.minutes(1)))
struct OpenCodeReplayTests {
  private func replay(_ name: String, _ scenario: (OpenCodeDriver, URL) async throws -> Void) async throws {
    let folder = URL(filePath: NSTemporaryDirectory()).appending(path: "loci-opencode-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let launcher = try ScriptedLauncher("OpenCode/\(name)", folder: folder)
    let driver = OpenCodeDriver(
      executable: URL(filePath: "/opencode"), launcher: launcher)
    try await scenario(driver, folder)
    launcher.verify()
  }

  @Test func aReplyArrivesAndTheTurnCompletes() async throws { try await replay("reply", OpenCodeScenario.reply) }
  @Test func aToolCallIsSeenFromStartToResult() async throws { try await replay("tool", OpenCodeScenario.tool) }
  @Test func anAllowedToolRuns() async throws {
    try await replay("permission-allow") { try await OpenCodeScenario.permission($0, $1, allow: true) }
  }
  @Test func aDeniedToolDoesNotRun() async throws {
    try await replay("permission-deny") { try await OpenCodeScenario.permission($0, $1, allow: false) }
  }
  @Test func interruptingStopsTheTurnAndAllowsAnotherReply() async throws {
    try await replay("interrupt") { try await OpenCodeScenario.interrupt($0, $1, asking: false) }
  }
  @Test func interruptingWithdrawsAnUnansweredRequest() async throws {
    try await replay("interrupt-asking") { try await OpenCodeScenario.interrupt($0, $1, asking: true) }
  }
  @Test func aResumedSessionRemembersWithoutReplayingOldText() async throws {
    try await replay("resume", OpenCodeScenario.resume)
  }
  @Test func resumingAMissingSessionFails() async throws {
    try await replay("resume-missing", OpenCodeScenario.missingSession)
  }
  @Test func anUnknownModelFails() async throws { try await replay("bad-model", OpenCodeScenario.unknownModel) }

  @Test func aProviderFailureEndsOnceAndIgnoresUpdatesFromAnotherSession() async throws {
    try await replay("synthetic-provider-error") { driver, folder in
      let session = try await driver.open(.init(workingDirectory: folder, permission: .full))
      let events = await Scenario.watch(try await session.send("Reply with exactly one word: pong"))
      #expect(events.reply == "partial")
      #expect(events.endings == [.failed(.provider("quota exhausted"))])
      #expect(events.last == .ended(.failed(.provider("quota exhausted"))))
      await session.close()
    }
  }

  @Test func anUnexpectedExitFailsTheTurnWithDiagnostics() async throws {
    try await replay("synthetic-died") { driver, folder in
      let session = try await driver.open(.init(workingDirectory: folder, permission: .full))
      let events = await Scenario.watch(try await session.send("Reply with exactly one word: pong"))
      #expect(events.endings == [.failed(.exited(code: 9, diagnostics: "broken"))])
      await session.close()
    }
  }

  @Test func aFinalReplyIsDeliveredBeforeAnExitThatFollowsItsCompletion() async throws {
    try await replay("synthetic-result-before-exit") { driver, folder in
      let session = try await driver.open(.init(workingDirectory: folder, permission: .full))
      let events = await Scenario.watch(try await session.send("Reply with exactly one word: pong"))
      #expect(events.reply == "last")
      #expect(events.endings == [.completed])
      #expect(events.last == .ended(.completed))
      await session.close()
    }
  }

  @Test func anUnexpectedExitWithdrawsEveryPermissionRequest() async throws {
    try await replay("synthetic-died-asking") { driver, folder in
      let session = try await driver.open(.init(workingDirectory: folder, permission: .ask))
      let events = await Scenario.watch(try await session.send("Reply with exactly one word: pong"))
      #expect(events.contains(.permissionClosed(.init("7"))))
      #expect(events.endings == [.failed(.exited(code: 9, diagnostics: "broken"))])
      await session.close()
    }
  }

  @Test func aLoadFailureForAnExistingSessionKeepsTheOriginalError() async throws {
    try await replay("synthetic-load-failed") { driver, folder in
      await #expect(throws: AgentError.rejected("Internal error: OpenCode service failure")) {
        _ = try await driver.open(
          .init(
            workingDirectory: folder, permission: .full,
            resume: .init(provider: .opencode, value: "ses_00000000000000000000000000")))
      }
    }
  }

  @Test func allSessionListPagesAreCheckedBeforeDeclaringASessionMissing() async throws {
    try await replay("synthetic-missing-paginated", OpenCodeScenario.missingSession)
  }
}
