import Foundation
import Testing

@testable import LociAgents

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["LOCI_CODEX"] != nil), .timeLimit(.minutes(3)))
struct CodexLiveTests {
  static let arguments = ["-c", "model_reasoning_effort=\"low\""]

  private func live(_ name: String, _ scenario: (Stage) async throws -> Void) async throws {
    let environment = ProcessInfo.processInfo.environment
    let folder = URL(filePath: NSTemporaryDirectory()).appending(path: "loci-codex-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let recorder = RecordingLauncher(folder: folder)
    let stage = Stage(
      driver: CodexDriver(
        executable: URL(filePath: environment["LOCI_CODEX"] ?? ""), arguments: Self.arguments, launcher: recorder),
      folder: folder)
    try await scenario(stage)
    if name == "allow" || name == "deny" || name == "interrupt-asking" {
      #expect(
        FileManager.default.fileExists(atPath: folder.appending(path: "approval-marker").path) == (name == "allow"))
    }
    if let directory = environment["LOCI_CODEX_RECORD"] {
      try await recorder.save(name, to: URL(filePath: directory))
    }
  }

  @Test func aReplyArrivesAndTheTurnCompletes() async throws { try await live("reply", CodexScenario.reply) }
  @Test func aToolCallIsSeenFromStartToResult() async throws { try await live("tool", CodexScenario.tool) }
  @Test func anAllowedToolRuns() async throws {
    try await live("allow") { try await CodexScenario.permission($0, allow: true) }
  }
  @Test func aDeniedToolDoesNotRun() async throws {
    try await live("deny") { try await CodexScenario.permission($0, allow: false) }
  }
  @Test func interruptingStopsTheTurnAndAllowsAnother() async throws {
    try await live("interrupt", CodexScenario.interrupted)
  }
  @Test func interruptingWithdrawsThePermission() async throws {
    try await live("interrupt-asking", CodexScenario.interruptedWhileAsking)
  }
  @Test func aResumedSessionRemembers() async throws { try await live("resume", CodexScenario.resumed) }
  @Test func resumingAMissingSessionFails() async throws { try await live("missing", CodexScenario.missing) }
}
