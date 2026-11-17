import Foundation
import Testing

@testable import LociAgents

@Suite(.timeLimit(.minutes(1)))
struct CodexReplayTests {
  private func replay(
    _ name: String, clock: any Clock<Duration> = ContinuousClock(), _ scenario: (Stage) async throws -> Void
  ) async throws {
    let folder = URL(filePath: NSTemporaryDirectory()).appending(path: "loci-codex-\(UUID().uuidString)")
    let launcher = try ScriptedLauncher("Codex/\(name)", folder: folder)
    let stage = Stage(
      driver: CodexDriver.codex(
        executable: URL(filePath: "/codex"), arguments: CodexLiveTests.arguments, launcher: launcher, clock: clock),
      folder: folder)
    try await scenario(stage)
    launcher.verify()
  }

  @Test func aReplyArrivesAndTheTurnCompletes() async throws { try await replay("reply", CodexScenario.reply) }
  @Test func aToolCallIsSeenFromStartToResult() async throws { try await replay("tool", CodexScenario.tool) }
  @Test func interruptingStopsTheTurnAndAllowsAnother() async throws {
    try await replay("interrupt", CodexScenario.interrupted)
  }
  @Test func aResumedSessionRemembers() async throws { try await replay("resume", CodexScenario.resumed) }
  @Test func resumingAMissingSessionFails() async throws { try await replay("missing", CodexScenario.missing) }

  @Test func anUnresponsiveCodexIsReportedAndStopped() async throws {
    try await replay("synthetic-silent", clock: ImpatientClock()) { stage in
      await #expect(throws: AgentError.unresponsive("initialize")) { try await stage.open() }
    }
  }

  @Test func aDyingProcessFailsTheTurnWithItsDiagnostics() async throws {
    try await replay("synthetic-died") { stage in
      let session = try await stage.open()
      let error = AgentError.exited(code: 9, diagnostics: "fatal: out of memory")
      let events = await Scenario.watch(try await session.send("Reply with exactly one word: pong"))
      #expect(events == [.text("Half a reply"), .ended(.failed(error))])
      await #expect(throws: error) { try await session.send("Still there?") }
      await session.close()
    }
  }

  @Test func aProviderFailureEndsTheTurnExactlyOnce() async throws {
    try await replay("synthetic-failed") { stage in
      let session = try await stage.open()
      let events = await Scenario.watch(try await session.send("Reply with exactly one word: pong"))
      #expect(events == [.notice(.message("Retrying")), .ended(.failed(.provider("Quota exhausted")))])
      await session.close()
    }
  }

  @Test func aRejectedMessageThrowsAndTheSessionCanContinue() async throws {
    try await replay("synthetic-rejected") { stage in
      let session = try await stage.open()
      await #expect(throws: AgentError.rejected("No model selected")) {
        try await session.send("Reply with exactly one word: pong")
      }
      let events = await Scenario.watch(try await session.send("Reply with exactly one word: pong"))
      #expect(events == [.ended(.completed)])
      await session.close()
    }
  }
}
