import Foundation
import Testing

@testable import LociAgents

/// The scenarios against recordings of the real Pi (made by `PiLiveTests`), and against a few hand-written
/// ones, named `synthetic-`, for things the real Pi will not do on request.
@Suite(.timeLimit(.minutes(1)))
struct PiReplayTests {
  private func replay(
    _ name: String, clock: any Clock<Duration> = ContinuousClock(), _ scenario: (Stage) async throws -> Void
  ) async throws {
    let folder = URL(filePath: NSTemporaryDirectory()).appending(path: "loci-pi-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let launcher = try ScriptedLauncher("Pi/\(name)", folder: folder)
    let stage = Stage(
      driver: PiDriver(
        executable: URL(filePath: "/pi"),
        arguments: PiLiveTests.arguments + ["--session-dir", folder.appending(path: "sessions").path],
        launcher: launcher, clock: clock),
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
    try await replay("resume-missing", Scenario.resumedMissing)
  }
  @Test func anUnknownModelFails() async throws { try await replay("bad-model", Scenario.unknownModel) }

  @Test func theReplyArrivesInPiecesNotAllAtOnce() async throws {
    try await replay("permission-deny") { stage in
      let session = try await stage.open(.ask)
      let events = await Scenario.watch(try await session.send(Scenario.shellPrompt)) { event in
        if case .permission(let request) = event { await session.answer(request.id, with: .chosen("deny")) }
      }
      #expect(events.filter { if case .text = $0 { true } else { false } }.count > 3)
      await session.close()
    }
  }

  @Test func whenPiDiesTheTurnFailsWithItsLastWords() async throws {
    try await replay("synthetic-died") { stage in
      let session = try await stage.open()

      let events = await Scenario.watch(try await session.send("Go on"))

      let death = AgentError.exited(code: 9, diagnostics: "fatal: out of memory")
      #expect(events == [.text("Half a sen"), .ended(.failed(death))])
      await #expect(throws: death) { try await session.send("Still there?") }
      await session.close()
    }
  }

  @Test func aPiThatNeverAnswersIsReportedAndStopped() async throws {
    try await replay("synthetic-silent", clock: ImpatientClock()) { stage in
      await #expect(throws: AgentError.unresponsive("get_state")) { _ = try await stage.open() }
    }
  }

  @Test func aRefusedMessageThrowsAndTheSessionCarriesOn() async throws {
    try await replay("synthetic-refused") { stage in
      let session = try await stage.open()

      await #expect(throws: AgentError.rejected("No model selected")) { try await session.send("Go on") }
      let handled = await Scenario.watch(try await session.send("/handled"))

      #expect(handled == [.ended(.completed)])
      await session.close()
    }
  }

  @Test func extensionDialogsBecomeRequestsNoticesOrAreDismissed() async throws {
    try await replay("synthetic-dialogs") { stage in
      let session = try await stage.open()

      let events = await Scenario.watch(try await session.send("Go on")) { event in
        guard case .permission(let request) = event else { return }
        await session.answer(request.id, with: .chosen("1"))
        await session.answer(request.id, with: .chosen("0"))
      }

      let branches = PermissionRequest(
        id: .init("pick"), title: "Which branch?",
        options: [.init(id: "0", role: .choice, label: "main"), .init(id: "1", role: .choice, label: "native")])
      #expect(
        events == [
          .notice(.message("Heads up")), .notice(.message("Your name?")), .permission(branches), .ended(.completed),
        ])
      await session.close()
    }
  }

  @Test func aRequestThatArrivesAfterInterruptingIsDismissedUnseen() async throws {
    try await replay("synthetic-late-request") { stage in
      let session = try await stage.open()

      let events = await Scenario.watch(try await session.send("Go on")) { event in
        if case .permission = event { await session.interrupt() }
      }

      let first = PermissionRequest(
        id: .init("first"), title: "Run it?",
        options: [.init(id: "allow", role: .allow), .init(id: "deny", role: .deny)])
      #expect(
        events == [
          .permission(first), .permissionClosed(first.id), .context(ContextUsage(used: 12, window: 1000)),
          .ended(.interrupted),
        ])
      await session.close()
    }
  }
}
