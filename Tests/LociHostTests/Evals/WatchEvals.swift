import Foundation
import LociMedia
import LociModel
import Testing

@testable import LociHost

/// The missed event of 11-27 on the real Codex of this Mac: the lunch break replayed into a project that holds
/// funds, triage asked through `codex exec` and the companion on Codex. The State Council's news must be a card
/// by 12:30 with 13:00 as its deadline, and the noise none. Skipped unless `LOCI_EVAL=1` and `LOCI_EVAL_GROUPS`
/// names `watch`; `script/eval` sets everything up.
@Suite(
  .serialized,
  .enabled(
    if: ProcessInfo.processInfo.environment["LOCI_EVAL"] == "1"
      && (ProcessInfo.processInfo.environment["LOCI_EVAL_GROUPS"] ?? "").contains("watch")))
struct WatchEvals {
  static let settings = ProcessInfo.processInfo.environment

  @Test(.timeLimit(.minutes(60))) func theMissedEventOn1127() async throws {
    let tool = try #require(Self.settings["LOCI_EVAL_TOOL"].map { URL(filePath: $0) }, "LOCI_EVAL_TOOL is not set")
    let out = try #require(Self.settings["LOCI_EVAL_OUT"].map { URL(filePath: $0) }, "LOCI_EVAL_OUT is not set")
    let codexPath = try #require(Self.settings["LOCI_EVAL_CODEX"], "LOCI_EVAL_CODEX is not set")
    let place = Place()
    let keep = Self.settings["LOCI_EVAL_KEEP"] == "1"
    defer { if !keep { place.remove() } }
    let sources = FakeSources()
    let world = TestWorld(agent: FakeAgent(provider: .codex), sources: sources)
    let agentTool = AgentTool(folder: tool, socket: DataFolder.socket(in: place.root))
    let installed = InstalledAgents(tool: agentTool)
    let codex = try #require(await installed.driver(for: .codex), "Codex is not installed on this Mac")
    let environment = HostEnvironment(
      newID: { world.nextID() }, now: { world.now }, timeZone: TestWorld.timeZone,
      defaultRuntime: Runtime(provider: .codex), discard: .permanently,
      agents: { $0 == .codex ? codex : nil }, detectAgents: { await installed.detect(again: $0) },
      ticks: world.environment.ticks, media: .disconnected(sources: sources), tool: agentTool,
      modelKeys: MemoryModelKeys(), modelClient: ModelClient(network: CodexToolModel(codex: URL(filePath: codexPath))))
    let host = try await LocalHost.start(root: place.root, database: place.database, environment: environment)
    let outcome: WatchReplay.Outcome
    do {
      _ = try await configureModels(host)
      let project = try await ProjectScenarioTests.start(host, named: "理财", summary: "指数基金和 QDII，长期收益与理财认知")
      try Data(WatchSample.watch.utf8).write(to: place.root.appending(path: "agent/projects/\(project)/WATCH.md"))
      _ = await Background.call(SaveDataSource(Watching.news), from: .conversation(.project(project)), on: host)
      outcome = try await WatchReplay(
        host: host, world: world, sources: sources, sample: .middayOf1127, home: .project(project),
        patience: .seconds(900)
      ).run()
    } catch {
      await host.close()
      throw error
    }
    await host.close()
    let problems = WatchReplay.problems(outcome, against: .middayOf1127)
    try Self.report(outcome, problems: problems, to: out)
    if keep { try Data(place.root.path.utf8).write(to: out.appending(path: "watch-data-folder.txt")) }
    #expect(problems.isEmpty)
  }

  static func report(_ outcome: WatchReplay.Outcome, problems: [String], to folder: URL) throws {
    let zone = WatchSample.zone
    let cards = outcome.cards.map { card in
      "- \(card.createdAt.iso8601(in: zone)) 截止 \(card.deadline?.iso8601(in: zone) ?? "无")：\(card.what)"
        + (card.question.map { " / \($0)" } ?? "")
    }
    let findings = outcome.findings.map { "- `\($0.key)`：\($0.summary)（\($0.reason)）" }
    let lines =
      ["# 错过的事件：11-27 午间回放", "", problems.isEmpty ? "通过。" : "没通过：", ""]
      + problems.map { "- \($0)" } + ["", "## 卡片", ""] + (cards.isEmpty ? ["（没有）"] : cards)
      + ["", "## 分拣升级", ""] + (findings.isEmpty ? ["（没有）"] : findings)
      + ["", "伙伴被叫醒 \(outcome.runs) 次。", "", "样本里只有 12:24:51 那条是财联社原文，其余为标明的编造噪音。"]
    try Data(lines.joined(separator: "\n").utf8).write(to: folder.appending(path: "watch-report.md"))
  }
}

/// The tool model, answered by `codex exec` on this Mac: each request's prompt is one ephemeral, read-only
/// Codex session, whose last message is the reply.
struct CodexToolModel: Network {
  let codex: URL

  func data(for request: URLRequest) async throws(FetchError) -> (Data, HTTPURLResponse) {
    guard let url = request.url,
      let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
    else { throw FetchError(reason: "no url") }
    if request.httpMethod == "GET" { return (Data(#"{"data":[{"id":"fixture"}]}"#.utf8), response) }
    guard let body = request.httpBody,
      let payload = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
      let prompt = (payload["messages"] as? [[String: String]])?.first?["content"]
    else { throw FetchError(reason: "not a chat request") }
    guard let reply = await ask(prompt) else { throw FetchError(reason: "codex exec gave no answer") }
    guard let data = try? JSONEncoder().encode(["choices": [["message": ["content": reply]]]]) else {
      throw FetchError(reason: "could not encode")
    }
    return (data, response)
  }

  func download(_ request: URLRequest, progress: @escaping @Sendable (Fraction?) -> Void) async throws(FetchError)
    -> URL
  {
    throw FetchError(reason: "no downloads")
  }

  private func ask(_ prompt: String) async -> String? {
    let reply = FileManager.default.temporaryDirectory.appending(path: "loci-eval-triage-\(UUID().uuidString).txt")
    defer { try? FileManager.default.removeItem(at: reply) }
    let process = Process()
    process.executableURL = codex
    process.arguments = [
      "exec", "--ephemeral", "--skip-git-repo-check", "--sandbox", "read-only", "--output-last-message", reply.path,
      prompt,
    ]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    let finished = await withCheckedContinuation { (done: CheckedContinuation<Bool, Never>) in
      process.terminationHandler = { done.resume(returning: $0.terminationStatus == 0) }
      do { try process.run() } catch { done.resume(returning: false) }
    }
    return finished ? try? String(contentsOf: reply, encoding: .utf8) : nil
  }
}
