import Foundation
import LociAgents
import LociModel
import LociStore
import Testing

@testable import LociHost

/// US-S1, US-S5, US-S8: the usage page reads the files the CLIs keep of the companion's sessions.
@Suite(.timeLimit(.minutes(1)))
struct UsageScenarioTests {
  private static let reading = [
    #"{"type":"user","message":{"content":"Refresh the panel."}}"#,
    #"{"type":"assistant","message":{"id":"m1","content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"gh pr list"}}],"usage":{"input_tokens":2,"cache_creation_input_tokens":1000,"cache_read_input_tokens":20000,"output_tokens":40}}}"#,
    #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"three pull requests"}]}}"#,
    #"{"type":"assistant","message":{"id":"m2","content":[],"usage":{"input_tokens":2,"cache_creation_input_tokens":300,"cache_read_input_tokens":21002,"output_tokens":20}}}"#,
  ].joined(separator: "\n")
  private static let saving = reading.replacingOccurrences(of: "gh pr list", with: #"\"$LOCI\" panel save radar"#)

  @Test func eachSessionWithAFileIsReadAndToldWhatItWasFor() async throws {
    let cli = try ScratchCLI()
    defer { cli.remove() }
    try cli.claudeCode("main-1", Self.reading)
    try cli.claudeCode("radar-1", Self.reading)
    try cli.claudeCode("radar-2", Self.saving)
    try cli.claudeCode("review-1", Self.saving)
    try await withHost(sessionFiles: cli.folders) { host, _, world in
      let day = try #require(Day("2025-11-16"))
      let sessions: [(SessionOwner, Provider, String, Int64)] = [
        (.conversation(.main), .claudeCode, "main-1", 0), (.panel("radar"), .claudeCode, "radar-1", 60_000),
        (.panel("radar"), .claudeCode, "radar-2", 120_000), (.review(day), .claudeCode, "review-1", 180_000),
        (.conversation(.main), .pi, "pi-1", 240_000), (.panel("radar"), .claudeCode, "old", -86_400_000),
      ]
      for (owner, provider, handle, offset) in sessions {
        try host.database.start(
          SessionRecord(
            id: world.nextID(), owner: owner, runtime: Runtime(provider: provider, model: "opus"),
            handle: handle, instructions: "hash",
            startedAt: Timestamp(millisecondsSince1970: world.now.millisecondsSince1970 + offset)))
      }
      try host.database.beginReview(of: day, at: world.now)
      try host.database.endReview(of: day, .failed("the CLI stopped"))

      let usage = try await host.run(ReadUsage(since: world.now))

      #expect(usage.map(\.activity) == [.review, .panel("radar"), .panel("radar"), .main])
      #expect(usage.map(\.outcome) == [.failed, .made, .nothingNew, nil])
      #expect(usage.map(\.title) == [nil, "radar", "radar", nil])
      let main = try #require(usage.last)
      #expect(main.model == "opus")
      #expect(main.calls == 2)
      #expect(main.tokens == TokenCounts(input: 4, cacheWrite: 1300, cacheRead: 41002, output: 60))
      #expect(main.context == ContextSpan(start: 21002, end: 21304, peak: 21304))
      #expect(main.makeup.contains(ContextPart(.tool("gh"), tokens: 262)))
    }
  }

  @Test func aCLIThatKeepsNoFileLeavesThePageEmpty() async throws {
    try await withHost { host, _, world in
      try host.database.start(
        SessionRecord(
          id: world.nextID(), owner: .conversation(.main), runtime: Runtime(provider: .claudeCode), handle: "a",
          instructions: "hash", startedAt: world.now))

      #expect(try await host.run(ReadUsage(since: world.now)).isEmpty)
    }
  }
}

/// A folder standing in for where Claude Code keeps its session files.
private struct ScratchCLI {
  let root = FileManager.default.temporaryDirectory.appending(path: "loci-cli-\(UUID().uuidString)")

  init() throws {
    try FileManager.default.createDirectory(
      at: root.appending(path: "projects/-Users-x-Loci-agent"), withIntermediateDirectories: true)
  }

  var folders: SessionFolders {
    SessionFolders(claudeCode: root.appending(path: "projects"), codex: root.appending(path: "sessions"))
  }

  func claudeCode(_ handle: String, _ text: String) throws {
    try Data(text.utf8).write(to: root.appending(path: "projects/-Users-x-Loci-agent/\(handle).jsonl"))
  }

  func remove() {
    try? FileManager.default.removeItem(at: root)
  }
}
