import Foundation
import Testing

@testable import LociAgents

/// The scenarios against the real Grok. Skipped unless `LOCI_GROK` holds the path to `grok`; they spend a
/// little of whatever model Grok is set up to use. With `LOCI_GROK_RECORD` set to a folder, each one also
/// saves the conversation there as a fixture for `GrokReplayTests`.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["LOCI_GROK"] != nil), .timeLimit(.minutes(3)))
struct GrokLiveTests {
  private func live(_ name: String, _ scenario: (Stage) async throws -> Void) async throws {
    let environment = ProcessInfo.processInfo.environment
    let folder = URL(filePath: NSTemporaryDirectory()).appending(path: "loci-grok-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let recorder = RecordingLauncher(folder: folder)
    let stage = Stage(
      driver: AcpDriver.grok(executable: URL(filePath: environment["LOCI_GROK"] ?? ""), launcher: recorder),
      folder: folder)

    try await scenario(stage)

    if let directory = environment["LOCI_GROK_RECORD"] {
      try await recorder.save(name, to: URL(filePath: directory))
    }
  }

  @Test func aReplyArrivesAndTheTurnCompletes() async throws { try await live("reply", Scenario.reply) }
  @Test func aToolCallIsSeenFromStartToResult() async throws { try await live("tool", GrokScenario.tool) }
  @Test func interruptingStopsTheTurn() async throws { try await live("interrupt", Scenario.interrupted) }
  @Test func aResumedSessionRemembers() async throws { try await live("resume", Scenario.resumed) }
  @Test func resumingAMissingSessionFails() async throws {
    try await live("resume-missing", GrokScenario.resumedMissing)
  }
}
