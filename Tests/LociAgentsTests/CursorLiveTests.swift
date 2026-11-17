import Foundation
import Testing

@testable import LociAgents

/// Runs the real, already authenticated Cursor only when LOCI_CURSOR supplies its executable path.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["LOCI_CURSOR"] != nil), .timeLimit(.minutes(3)))
struct CursorLiveTests {
  private func live(_ name: String, _ scenario: (Stage) async throws -> Void) async throws {
    let environment = ProcessInfo.processInfo.environment
    let folder = URL(filePath: NSTemporaryDirectory()).appending(path: "loci-cursor-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let recorder = RecordingLauncher(folder: folder)
    let stage = Stage(
      driver: AcpDriver.cursor(executable: URL(filePath: environment["LOCI_CURSOR"] ?? ""), launcher: recorder),
      folder: folder)
    try await scenario(stage)
    if let directory = environment["LOCI_CURSOR_RECORD"] {
      try await recorder.save("cursor-\(name)", to: URL(filePath: directory))
    }
  }

  @Test func aReplyArrivesAndTheTurnCompletes() async throws { try await live("reply", CursorScenario.reply) }
  @Test func aToolCallIsSeenFromStartToResult() async throws { try await live("tool", CursorScenario.tool) }
  @Test func anAllowedToolRuns() async throws {
    try await live("permission-allow", CursorScenario.permissionAllowed)
  }
  @Test func aDeniedToolDoesNotRun() async throws {
    try await live("permission-deny", CursorScenario.permissionDenied)
  }
  @Test func interruptingStopsTheTurn() async throws { try await live("interrupt", Scenario.interrupted) }
  @Test func interruptingWithdrawsAnUnansweredRequest() async throws {
    try await live("interrupt-asking", Scenario.interruptedWhileAsking)
  }
  @Test func aResumedSessionRemembers() async throws { try await live("resume", CursorScenario.resumed) }
}
