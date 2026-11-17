import Foundation
import LociModel
import Testing

@testable import LociAgents

/// Contract examples based on the old Hermes adapter, not recordings of a real Hermes process.
@Suite(.timeLimit(.minutes(1)))
struct HermesReplayTests {
  private func replay(_ name: String, _ scenario: (Stage) async throws -> Void) async throws {
    let folder = URL(filePath: NSTemporaryDirectory()).appending(path: "loci-hermes-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let launcher = try ScriptedLauncher("Hermes/synthetic-\(name)", folder: folder)
    let stage = Stage(
      driver: AcpDriver.hermes(executable: URL(filePath: "/hermes"), launcher: launcher), folder: folder)
    try await scenario(stage)
    launcher.verify()
  }

  @Test func aReplyArrivesAndTheTurnCompletes() async throws { try await replay("reply", HermesScenario.reply) }
  @Test func aToolCallIsSeenFromStartToResult() async throws { try await replay("tool", HermesScenario.tool) }
  @Test func interruptingStopsTheTurnAndAllowsAnother() async throws {
    try await replay("interrupt", HermesScenario.interrupted)
  }
  @Test func aResumedSessionRemembersWithoutRepeatingHistory() async throws {
    try await replay("resume") { stage in
      let first = try await stage.open()
      let taught = await Scenario.watch(try await first.send("Remember this word: quokka. Reply with exactly: OK"))
      #expect(taught.last == .ended(.completed))
      await first.close()
      let second = try await stage.open(resume: first.handle)
      #expect(second.handle == first.handle)
      let asked = await Scenario.watch(
        try await second.send("Which word did I ask you to remember? Reply with just that word."))
      #expect(asked.reply == "quokka")
      #expect(asked.endings == [.completed])
      #expect(asked.last == .ended(.completed))
      await second.close()
    }
  }

  @Test func theRequestedModelAndModeAreSetBeforeTheFirstPrompt() async throws {
    try await replay("model") { stage in
      let session = try await stage.open(model: "some-model")
      #expect(session.handle.provider == .hermes)
      let events = await Scenario.watch(try await session.send("Reply with exactly one word: pong"))
      #expect(events.reply == "pong")
      #expect(events.contains(.context(ContextUsage(used: 7, window: 999))))
      #expect(events.last == .ended(.completed))
      await session.close()
    }
  }

  @Test func aFailedModeSelectionDoesNotExposeAnUnconfiguredSession() async throws {
    try await replay("mode-refused") { stage in
      await #expect(throws: AgentError.rejected("Unsupported mode")) { _ = try await stage.open() }
    }
  }

  @Test func aFailedLoadDoesNotCreateANewConversation() async throws {
    try await replay("resume-missing") { stage in
      await #expect(throws: AgentError.rejected("Session not found")) {
        _ = try await stage.open(resume: .init(provider: .hermes, value: "missing"))
      }
    }
  }

  @Test func aFailedModelSelectionDoesNotSilentlyUseTheDefault() async throws {
    try await replay("model-refused") { stage in
      await #expect(throws: AgentError.rejected("Unknown model")) { _ = try await stage.open(model: "unknown") }
    }
  }

  @Test func aSessionFromAnotherProviderIsRejectedBeforeLaunching() async throws {
    let driver = AcpDriver.hermes(executable: URL(filePath: "/nonexistent/hermes"))
    await #expect(throws: AgentError.sessionNotFound) {
      _ = try await driver.open(
        SessionConfiguration(
          workingDirectory: URL(filePath: "/tmp"), resume: .init(provider: .grok, value: "other")))
    }
  }
}
