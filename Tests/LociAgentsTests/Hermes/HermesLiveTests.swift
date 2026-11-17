import Foundation
import Testing

@testable import LociAgents

/// Skipped unless `LOCI_HERMES` names the real executable. `LOCI_HERMES_RECORD` saves real protocol output.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["LOCI_HERMES"] != nil), .timeLimit(.minutes(3)))
struct HermesLiveTests {
  private func live(_ name: String, _ scenario: (Stage) async throws -> Void) async throws {
    let environment = ProcessInfo.processInfo.environment
    let folder = URL(filePath: NSTemporaryDirectory()).appending(path: "loci-hermes-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let recorder = RecordingLauncher(folder: folder)
    let stage = Stage(
      driver: AcpDriver.hermes(executable: URL(filePath: environment["LOCI_HERMES"] ?? ""), launcher: recorder),
      folder: folder)
    try await scenario(stage)
    if let directory = environment["LOCI_HERMES_RECORD"] {
      let destination = URL(filePath: directory)
      try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
      try await recorder.save(name, to: destination)
    }
  }

  @Test func aReplyArrivesAndTheTurnCompletes() async throws { try await live("reply", HermesScenario.reply) }
  @Test func aToolCallIsSeenFromStartToResult() async throws { try await live("tool", HermesScenario.tool) }
  @Test func anAllowedToolRuns() async throws { try await live("permission-allow", HermesScenario.permissionAllowed) }
  @Test func aDeniedToolDoesNotRun() async throws { try await live("permission-deny", HermesScenario.permissionDenied) }
  @Test func interruptingStopsTheTurnAndAllowsAnother() async throws {
    try await live("interrupt", HermesScenario.interrupted)
  }
  @Test func interruptingWithdrawsAnUnansweredRequest() async throws {
    try await live("interrupt-asking", HermesScenario.interruptedWhileAsking)
  }
  @Test func aResumedSessionRemembers() async throws { try await live("resume", Scenario.resumed) }
  @Test func aMissingSessionFailsInsteadOfStartingAnother() async throws {
    try await live("resume-missing") { stage in
      await #expect(throws: AgentError.self) {
        _ = try await stage.open(resume: .init(provider: .hermes, value: "019a0000-0000-7000-8000-000000000000"))
      }
    }
  }
}
