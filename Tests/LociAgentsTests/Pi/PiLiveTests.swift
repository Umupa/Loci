import Foundation
import Testing

@testable import LociAgents

/// The scenarios against the real Pi. Skipped unless `LOCI_PI` holds the path to `pi`; they spend a little
/// of whatever model Pi is set up to use. With `LOCI_PI_RECORD` set to a folder, each one also saves the
/// conversation there as a fixture for `PiReplayTests`.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["LOCI_PI"] != nil), .timeLimit(.minutes(3)))
struct PiLiveTests {
  /// Leaves the person's own extensions, skills and project files out, so a run depends only on Pi.
  static let arguments = ["--no-extensions", "--no-skills", "--no-context-files", "--thinking", "low"]

  private func live(_ name: String, _ scenario: (Stage) async throws -> Void) async throws {
    let environment = ProcessInfo.processInfo.environment
    let folder = URL(filePath: NSTemporaryDirectory()).appending(path: "loci-pi-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let sessions = folder.appending(path: "sessions").path
    let recorder = RecordingLauncher(folder: folder)
    let stage = Stage(
      driver: PiDriver(
        executable: URL(filePath: environment["LOCI_PI"] ?? ""),
        arguments: Self.arguments + ["--session-dir", sessions], launcher: recorder),
      folder: folder)

    try await scenario(stage)

    if let directory = environment["LOCI_PI_RECORD"] {
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
  @Test func resumingAMissingSessionFails() async throws { try await live("resume-missing", Scenario.resumedMissing) }
  @Test func anUnknownModelFails() async throws { try await live("bad-model", Scenario.unknownModel) }
}
