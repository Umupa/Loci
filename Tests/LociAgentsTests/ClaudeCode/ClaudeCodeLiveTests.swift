import Foundation
import Testing

@testable import LociAgents

@Suite(
  .serialized, .enabled(if: ProcessInfo.processInfo.environment["LOCI_CLAUDE_CODE"] != nil), .timeLimit(.minutes(3)))
struct ClaudeCodeLiveTests {
  static let arguments = [
    "--model", "haiku", "--effort", "low", "--max-turns", "4", "--max-budget-usd", "0.50",
    "--setting-sources", "user", "--settings", "{\"disableAllHooks\":true,\"permissions\":{\"ask\":[\"Bash\"]}}",
    "--strict-mcp-config", "--mcp-config", "{\"mcpServers\":{}}",
  ]

  private func live(_ name: String, _ scenario: (Stage) async throws -> Void) async throws {
    let environment = ProcessInfo.processInfo.environment
    let folder = URL(filePath: NSTemporaryDirectory()).appending(path: "loci-claude-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let recorder = RecordingLauncher(folder: folder)
    let stage = Stage(
      driver: ClaudeCodeDriver.claudeCode(
        executable: URL(filePath: environment["LOCI_CLAUDE_CODE"] ?? ""), arguments: Self.arguments,
        launcher: recorder, makeSessionID: { ClaudeCodeScenario.sessionID }), folder: folder)
    try await scenario(stage)
    if let directory = environment["LOCI_CLAUDE_CODE_RECORD"] {
      try await recorder.save(name, to: URL(filePath: directory))
    }
  }

  @Test func aReplyArrivesAndCompletes() async throws { try await live("reply", ClaudeCodeScenario.reply) }
  @Test func aToolRunsAndReturnsItsResult() async throws { try await live("tool", ClaudeCodeScenario.tool) }
  @Test func interruptingLeavesTheSessionUsable() async throws {
    try await live("interrupt", ClaudeCodeScenario.interrupted)
  }
  @Test func aResumedSessionRemembers() async throws { try await live("resume", ClaudeCodeScenario.resumed) }
  @Test func aMissingSessionFails() async throws { try await live("missing", ClaudeCodeScenario.missing) }
}
