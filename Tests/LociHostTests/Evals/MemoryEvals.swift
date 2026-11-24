import Foundation
import LociMedia
import LociModel
import Testing

@testable import LociHost

/// The memory of 1.8.3 on the real Codex of this Mac: days of the person talking, each looked back on, then
/// questions; and what remembering costs. Skipped unless `LOCI_EVAL=1` and `LOCI_EVAL_GROUPS` names
/// `memory` or `cost`; `script/eval` sets everything up.
@Suite(
  .serialized,
  .enabled(
    if: ProcessInfo.processInfo.environment["LOCI_EVAL"] == "1"
      && (ProcessInfo.processInfo.environment["LOCI_EVAL_GROUPS"] ?? "").contains(/memory|cost/)))
struct MemoryEvals {
  static let settings = ProcessInfo.processInfo.environment

  @Test(.timeLimit(.minutes(120))) func theMemoryOnCodex() async throws {
    let tool = try #require(Self.settings["LOCI_EVAL_TOOL"].map { URL(filePath: $0) }, "LOCI_EVAL_TOOL is not set")
    let out = try #require(Self.settings["LOCI_EVAL_OUT"].map { URL(filePath: $0) }, "LOCI_EVAL_OUT is not set")
    let codexPath = try #require(Self.settings["LOCI_EVAL_CODEX"], "LOCI_EVAL_CODEX is not set")
    let place = Place()
    let keep = Self.settings["LOCI_EVAL_KEEP"] == "1"
    defer { if !keep { place.remove() } }
    let world = TestWorld(agent: FakeAgent(provider: .codex))
    let agentTool = AgentTool(folder: tool, socket: DataFolder.socket(in: place.root))
    let installed = InstalledAgents(tool: agentTool)
    let codex = try #require(await installed.driver(for: .codex), "Codex is not installed on this Mac")
    let environment = HostEnvironment(
      newID: { world.nextID() }, now: { world.now }, timeZone: TestWorld.timeZone,
      defaultRuntime: Runtime(provider: .codex), discard: .permanently,
      agents: { $0 == .codex ? codex : nil }, detectAgents: { await installed.detect(again: $0) },
      ticks: world.environment.ticks, tool: agentTool)
    let host = try await LocalHost.start(root: place.root, database: place.database, environment: environment)
    let runner = MemoryEvalRunner(
      host: host, place: place, world: world, scenario: .standard,
      judge: CodexMemoryJudge(codex: URL(filePath: codexPath)), patience: .seconds(900))
    let outcome: MemoryOutcome
    do {
      outcome = try await runner.run()
    } catch {
      await host.close()
      throw error
    }
    await host.close()
    try MemoryReport.write(outcome, runtime: "codex", to: out)
    if keep { try Data(place.root.path.utf8).write(to: out.appending(path: "memory-data-folder.txt")) }
    #expect(!outcome.answers.isEmpty)
  }
}

/// Asks the Codex on this Mac whether an answer holds its fact, with `memory-judge.md` beside this file.
struct CodexMemoryJudge: MemoryJudge {
  let codex: URL

  static let prompt = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "memory-judge.md")

  func grade(_ question: MemoryScenario.Question, answer: String) async -> Bool? {
    guard let template = try? String(contentsOf: Self.prompt, encoding: .utf8) else { return nil }
    let text = template.replacing("{{question}}", with: question.ask).replacing("{{fact}}", with: question.fact)
      .replacing("{{answer}}", with: answer)
    let reply = FileManager.default.temporaryDirectory.appending(path: "loci-eval-grade-\(UUID().uuidString).txt")
    defer { try? FileManager.default.removeItem(at: reply) }
    let process = Process()
    process.executableURL = codex
    process.arguments = [
      "exec", "--ephemeral", "--skip-git-repo-check", "--sandbox", "read-only", "--output-last-message", reply.path,
      text,
    ]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    let finished = await withCheckedContinuation { (done: CheckedContinuation<Bool, Never>) in
      process.terminationHandler = { done.resume(returning: $0.terminationStatus == 0) }
      do { try process.run() } catch { done.resume(returning: false) }
    }
    guard finished, let said = try? String(contentsOf: reply, encoding: .utf8) else { return nil }
    if said.contains("\"right\": true") || said.contains("\"right\":true") { return true }
    if said.contains("\"right\": false") || said.contains("\"right\":false") { return false }
    return nil
  }
}
