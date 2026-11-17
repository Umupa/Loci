import Foundation
import Testing

@testable import LociAgents

/// Runs against the real ACP server only when `LOCI_ANTIGRAVITY` names its executable.
@Suite(
  .serialized, .enabled(if: ProcessInfo.processInfo.environment["LOCI_ANTIGRAVITY"] != nil), .timeLimit(.minutes(3)))
struct AntigravityLiveTests {
  private func live(_ name: String, _ scenario: (Stage) async throws -> Void) async throws {
    let environment = ProcessInfo.processInfo.environment
    let folder = URL(filePath: NSTemporaryDirectory()).appending(path: "loci-antigravity-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let recorder = RecordingLauncher(folder: folder)
    let stage = Stage(
      driver: AcpDriver.antigravity(
        executable: URL(filePath: environment["LOCI_ANTIGRAVITY"] ?? ""), launcher: recorder), folder: folder)
    try await scenario(stage)
    if let directory = environment["LOCI_ANTIGRAVITY_RECORD"] {
      let destination = URL(filePath: directory)
      try await recorder.save(name, to: destination)
      let file = destination.appending(path: "\(name).jsonl")
      let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n").map { line in
        let step = try JSONDecoder().decode(JSONValue.self, from: Data(line.utf8))
        if let code = step["exit"] { return Recording.line(.object(["exit": code, "stderr": .string("")])) }
        return String(line)
      }
      try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: file)
    }
  }

  @Test func aReplyArrivesAndTheTurnCompletes() async throws { try await live("reply", Scenario.reply) }
  @Test func aToolCallIsSeenFromStartToResult() async throws { try await live("tool", AntigravityScenario.tool) }
  @Test func interruptingStopsTheTurn() async throws { try await live("interrupt", Scenario.interrupted) }
  @Test func aResumedSessionRemembers() async throws { try await live("resume", Scenario.resumed) }
  @Test func resumingAMissingSessionFails() async throws {
    try await live("resume-missing", AntigravityScenario.resumedMissing)
  }
  @Test func anUnknownModelFails() async throws { try await live("bad-model", AntigravityScenario.unknownModel) }
}
