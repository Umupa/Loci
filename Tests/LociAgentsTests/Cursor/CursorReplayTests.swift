import Foundation
import LociModel
import Testing

@testable import LociAgents

/// Hand-written protocol cases based on Cursor's ACP contract, not recordings of a real Cursor.
@Suite(.timeLimit(.minutes(1)))
struct CursorReplayTests {
  private func replay(_ name: String, _ scenario: (Stage) async throws -> Void) async throws {
    let folder = URL(filePath: NSTemporaryDirectory()).appending(path: "loci-cursor-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let launcher = try ScriptedLauncher("Cursor/synthetic-\(name)", folder: folder)
    let stage = Stage(
      driver: AcpDriver.cursor(executable: URL(filePath: "/cursor-agent"), launcher: launcher), folder: folder)

    try await scenario(stage)

    launcher.verify()
  }

  @Test func aReplyArrivesAndTheTurnCompletes() async throws { try await replay("reply", CursorScenario.reply) }
  @Test func aToolCallIsSeenFromStartToResult() async throws { try await replay("tool", CursorScenario.tool) }
  @Test func interruptingStopsTheTurnAndTheSessionCanContinue() async throws {
    try await replay("interrupt", Scenario.interrupted)
  }
  @Test func aLoadedSessionRemembersWithoutReplayingOldText() async throws {
    try await replay("resume", CursorScenario.resumed)
  }
  @Test func aFailedLoadIsReportedWithoutStartingANewConversation() async throws {
    try await replay("resume-failed") { stage in
      await #expect(throws: AgentError.rejected("Conversation missing")) {
        _ = try await stage.open(resume: SessionHandle(provider: .cursor, value: "cursor-1"))
      }
    }
  }
  @Test func unsupportedRequestsAreRefusedWithoutBlockingTheTurn() async throws {
    try await replay("unsupported", CursorScenario.reply)
  }
  @Test func anAuthenticationFailureIsReportedBeforeCreatingASession() async throws {
    try await replay("auth-failed") { stage in
      await #expect(throws: AgentError.rejected("Sign in to Cursor")) { _ = try await stage.open() }
    }
  }
  @Test func theSelectedModelUsesTheConfigOptionAdvertisedByCursor() async throws {
    try await replay("model") { stage in
      let session = try await stage.open(model: "some-model")
      #expect(session.handle.provider == .cursor)
      await session.close()
    }
  }
  @Test func anOlderCursorCanSelectAModelWhenConfigOptionsAreAbsent() async throws {
    try await replay("model-fallback") { stage in
      let session = try await stage.open(model: "some-model")
      await session.close()
    }
  }
  @Test func aRejectedModelIsReportedInsteadOfSilentlyUsingTheDefault() async throws {
    try await replay("model-failed") { stage in
      await #expect(throws: AgentError.rejected("Unknown model")) {
        _ = try await stage.open(model: "nope/none")
      }
    }
  }
  @Test func fullPermissionAnswersOnlyRequestsFromItsOwnSession() async throws {
    try await replay("permission-full") { stage in
      let session = try await stage.open()
      let events = await Scenario.watch(try await session.send(Scenario.shellPrompt))
      #expect(!events.contains { if case .permission = $0 { true } else { false } })
      #expect(events.reply == "loci-42")
      #expect(events.outputs.contains { $0.text.contains("loci-42") && !$0.failed })
      #expect(events.last == .ended(.completed))
      await session.close()
    }
  }
  @Test func aSessionFromAnotherProviderIsRejectedBeforeLaunchingCursor() async throws {
    try await replay("wrong-provider") { stage in
      await #expect(throws: AgentError.sessionNotFound) {
        _ = try await stage.open(resume: SessionHandle(provider: .grok, value: "other"))
      }
    }
  }

  @Test func fullPermissionFallsBackToPermanentApprovalWhenItIsTheOnlyAllowOption() async throws {
    try await replay("permission-full-always") { stage in
      let session = try await stage.open()
      let events = await Scenario.watch(try await session.send(Scenario.shellPrompt))
      #expect(events.reply == "loci-42")
      #expect(events.endings == [.completed])
      #expect(!events.contains { if case .permission = $0 { true } else { false } })
      await session.close()
    }
  }
}
