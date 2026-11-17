import Foundation
import Testing

@testable import LociAgents

/// Runs against omp only when `LOCI_OMP` names its executable; `LOCI_OMP_RECORD` saves the protocol.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["LOCI_OMP"] != nil), .timeLimit(.minutes(3)))
struct OmpLiveTests {
  static let arguments = ["--no-extensions", "--no-skills", "--no-rules", "--thinking", "low"]

  private func live(_ name: String, _ scenario: (Stage) async throws -> Void) async throws {
    let environment = ProcessInfo.processInfo.environment
    let folder = URL(filePath: NSTemporaryDirectory()).appending(path: "loci-omp-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let recorder = RecordingLauncher(folder: folder)
    let stage = Stage(
      driver: PiDriver.omp(
        executable: URL(filePath: environment["LOCI_OMP"] ?? ""),
        arguments: Self.arguments + ["--session-dir", folder.appending(path: "sessions").path], launcher: recorder),
      folder: folder)

    try await scenario(stage)

    if let directory = environment["LOCI_OMP_RECORD"] {
      try await recorder.save(name, to: URL(filePath: directory))
    }
  }

  @Test func aReplyArrivesAndTheTurnCompletes() async throws { try await live("reply", Scenario.reply) }
  @Test func aToolCallIsSeenFromStartToResult() async throws { try await live("tool", Scenario.tool) }
  @Test func anAllowedToolRuns() async throws { try await live("permission-allow", Scenario.permissionAllowed) }
  @Test func aDeniedToolDoesNotRun() async throws { try await live("permission-deny", Scenario.permissionDenied) }
  @Test func interruptingStopsTheTurn() async throws { try await live("interrupt", Scenario.interrupted) }
  @Test func interruptingWithdrawsAnUnansweredRequest() async throws {
    try await live("interrupt-asking", Scenario.interruptedWhileAsking)
  }
  @Test func aResumedSessionRemembers() async throws { try await live("resume", Scenario.resumed) }
  @Test func resumingAMissingSessionFails() async throws {
    try await live("resume-missing") { stage in
      let missing = SessionHandle(provider: .omp, value: Scenario.missingSession.value)
      await #expect(throws: AgentError.sessionNotFound) { _ = try await stage.open(resume: missing) }
    }
  }
  @Test func anUnknownModelFails() async throws { try await live("bad-model", Scenario.unknownModel) }
}
