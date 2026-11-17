import Foundation
import Testing

@testable import LociAgents

@Suite(.timeLimit(.minutes(1)))
struct ClaudeCodeReplayTests {
  private func replay(
    _ name: String, arguments: [String] = ClaudeCodeLiveTests.arguments,
    clock: any Clock<Duration> = ContinuousClock(), _ scenario: (Stage) async throws -> Void
  ) async throws {
    let folder = URL(filePath: NSTemporaryDirectory()).appending(path: "loci-claude-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let launcher = try ScriptedLauncher("ClaudeCode/\(name)", folder: folder)
    let stage = Stage(
      driver: ClaudeCodeDriver.claudeCode(
        executable: URL(filePath: "/claude"), arguments: arguments,
        launcher: launcher, clock: clock, makeSessionID: { ClaudeCodeScenario.sessionID }), folder: folder)
    try await scenario(stage)
    launcher.verify()
  }

  @Test func aReplyArrivesAndCompletes() async throws { try await replay("reply", ClaudeCodeScenario.reply) }
  @Test func aToolRunsAndReturnsItsResult() async throws { try await replay("tool", ClaudeCodeScenario.tool) }
  @Test func interruptingLeavesTheSessionUsable() async throws {
    try await replay("interrupt", ClaudeCodeScenario.interrupted)
  }
  @Test func aResumedSessionRemembers() async throws { try await replay("resume", ClaudeCodeScenario.resumed) }
  @Test func aMissingSessionFails() async throws { try await replay("missing", ClaudeCodeScenario.missing) }

  @Test func authenticationFailureEndsTheTurnWithTheProvidersWords() async throws {
    var arguments = ClaudeCodeLiveTests.arguments
    let sources = try #require(arguments.firstIndex(of: "--setting-sources"))
    let settings = try #require(arguments.firstIndex(of: "--settings"))
    arguments[sources + 1] = ""
    arguments[settings + 1] = "{\"disableAllHooks\":true}"
    try await replay("auth-error", arguments: arguments) { stage in
      let session = try await stage.open()
      let events = await Scenario.watch(try await session.send("Reply with exactly one word: pong"))
      let message = "Failed to authenticate: OAuth session expired and could not be refreshed"
      #expect(events.endings == [.failed(.provider(message))])
      await session.close()
    }
  }

  @Test func aProgramThatDiesFailsTheTurnAndRejectsMoreMessages() async throws {
    try await replay("synthetic-died") { stage in
      let session = try await stage.open()
      let events = await Scenario.watch(try await session.send("Go on"))
      let error = AgentError.exited(code: 9, diagnostics: "out of memory")
      #expect(events == [.text("Half a sentence"), .ended(.failed(error))])
      await #expect(throws: error) { try await session.send("Again") }
      await session.close()
    }
  }

  @Test func aSilentProgramTimesOutAndIsStopped() async throws {
    try await replay("synthetic-silent", clock: ImpatientClock()) { stage in
      await #expect(throws: AgentError.unresponsive("initialize")) { try await stage.open() }
    }
  }

  @Test func unknownControlRequestsAreRefusedAndTheConversationContinues() async throws {
    try await replay("synthetic-unknown-control") { stage in
      let session = try await stage.open()
      for text in ["Go on", "Again"] {
        let events = await Scenario.watch(try await session.send(text))
        #expect(events.reply == "pong")
        #expect(events.endings == [.completed])
      }
      await session.close()
    }
  }
}
