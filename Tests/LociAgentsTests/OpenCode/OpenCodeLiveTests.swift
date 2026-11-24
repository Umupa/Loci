import Foundation
import LociModel
import Testing

@testable import LociAgents

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["LOCI_OPENCODE"] != nil), .timeLimit(.minutes(3)))
struct OpenCodeLiveTests {
  private func live(_ name: String, _ scenario: (Stage) async throws -> Void) async throws {
    var environment = ProcessInfo.processInfo.environment
    let folder = URL(filePath: NSTemporaryDirectory()).appending(path: "loci-opencode-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    environment["OPENCODE_CONFIG_CONTENT"] = Recording.line(
      .object([
        "model": .string(environment["LOCI_OPENCODE_MODEL"] ?? "opencode/big-pickle"),
        "share": .string("disabled"), "autoupdate": .bool(false),
      ]))
    environment["XDG_DATA_HOME"] = folder.appending(path: "data").path
    environment["XDG_STATE_HOME"] = folder.appending(path: "state").path
    environment["XDG_CONFIG_HOME"] = folder.appending(path: "config").path
    environment["OPENCODE_DISABLE_EXTERNAL_SKILLS"] = "true"
    environment["OPENCODE_DISABLE_CLAUDE_CODE"] = "true"
    environment["OPENCODE_DISABLE_DEFAULT_PLUGINS"] = "true"
    let recorder = RecordingLauncher(folder: folder)
    let driver = AcpDriver.opencode(
      executable: URL(filePath: environment["LOCI_OPENCODE"] ?? ""), environment: environment, launcher: recorder)
    try await scenario(Stage(driver: driver, folder: folder))
    if let directory = environment["LOCI_OPENCODE_RECORD"] {
      try await recorder.save(name, to: URL(filePath: directory))
      let file = URL(filePath: directory).appending(path: "\(name).jsonl")
      let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n").map {
        Recording.line(Self.scrub(try JSONDecoder().decode(JSONValue.self, from: Data($0.utf8))))
      }
      try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: file)
    }
  }

  private static func scrub(_ value: JSONValue) -> JSONValue {
    switch value {
    case .object(let members):
      .object(
        members.mapValues(Self.scrub).merging(
          members["availableCommands"] == nil ? [:] : ["availableCommands": .array([])],
          uniquingKeysWith: { _, new in new }))
    case .array(let values): .array(values.map(Self.scrub))
    default: value
    }
  }

  @Test func aReplyArrivesAndTheTurnCompletes() async throws { try await live("reply", OpenCodeScenario.reply) }
  @Test func aToolCallIsSeenFromStartToResult() async throws { try await live("tool", OpenCodeScenario.tool) }
  @Test func interruptingStopsTheTurnAndAllowsAnotherReply() async throws {
    try await live("interrupt") { try await OpenCodeScenario.interrupt($0) }
  }
  @Test func aResumedSessionRemembersWithoutReplayingOldText() async throws {
    try await live("resume", OpenCodeScenario.resume)
  }
  @Test func resumingAMissingSessionFails() async throws {
    try await live("resume-missing", OpenCodeScenario.missingSession)
  }
  @Test func anUnknownModelFails() async throws { try await live("bad-model", OpenCodeScenario.unknownModel) }
}
