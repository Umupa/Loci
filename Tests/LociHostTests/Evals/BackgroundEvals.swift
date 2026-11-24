import Foundation
import LociMedia
import LociModel
import Testing

@testable import LociHost

/// The background runs of 1.8.0 on the real Codex of this Mac, day after day on a clock the eval moves, against
/// pages served on `127.0.0.1`. Skipped unless `LOCI_EVAL=1`; `script/eval` sets everything up.
///
/// - `LOCI_EVAL_TOOL`: the folder holding the `loci` command the runs call.
/// - `LOCI_EVAL_OUT`: where the report goes.
/// - `LOCI_EVAL_GROUPS`: the groups, separated by commas; this suite runs `quiet` and `repeat` (default both).
/// - `LOCI_EVAL_KEEP=1`: keeps each group's data folder and says where.
@Suite(
  .serialized,
  .enabled(
    if: ProcessInfo.processInfo.environment["LOCI_EVAL"] == "1"
      && (ProcessInfo.processInfo.environment["LOCI_EVAL_GROUPS"] ?? "quiet").contains(/quiet|repeat/)))
struct BackgroundEvals {
  static let settings = ProcessInfo.processInfo.environment

  @Test(.timeLimit(.minutes(90))) func theBackgroundRunsOnCodex() async throws {
    let tool = try #require(Self.settings["LOCI_EVAL_TOOL"].map { URL(filePath: $0) }, "LOCI_EVAL_TOOL is not set")
    let out = try #require(Self.settings["LOCI_EVAL_OUT"].map { URL(filePath: $0) }, "LOCI_EVAL_OUT is not set")
    let groups = (Self.settings["LOCI_EVAL_GROUPS"] ?? "quiet,repeat").split(separator: ",")
      .compactMap { EvalScenario.Group(rawValue: String($0)) }
    var outcomes: [EvalOutcome] = []
    for group in groups {
      outcomes.append(try await Self.run(group, tool: tool, out: out))
      try EvalReport.write(outcomes, runtime: "codex", to: out)
    }
    #expect(!outcomes.isEmpty)
  }

  /// One group in a new data folder, with only the clock and the pages made up.
  static func run(_ group: EvalScenario.Group, tool folder: URL, out: URL) async throws -> EvalOutcome {
    let place = Place()
    let keep = settings["LOCI_EVAL_KEEP"] == "1"
    defer { if !keep { place.remove() } }
    let world = TestWorld(agent: FakeAgent(provider: .codex))
    let tool = AgentTool(folder: folder, socket: DataFolder.socket(in: place.root))
    let installed = InstalledAgents(tool: tool)
    let codex = try #require(await installed.driver(for: .codex), "Codex is not installed on this Mac")
    let driver = EvalDriver(codex)
    let pages = try await EvalPages.start()
    defer { pages.stop() }
    let media = MediaEnvironment(
      support: place.root.appending(path: "support"), runner: SystemRunner(), network: SystemNetwork.anonymous(),
      transcriber: FakeTranscriber([]), searchPaths: [], readerLanguage: "zh-Hans")
    let environment = HostEnvironment(
      newID: { world.nextID() }, now: { world.now }, timeZone: TestWorld.timeZone,
      defaultRuntime: Runtime(provider: .codex), discard: .permanently,
      agents: { $0 == .codex ? driver : nil }, detectAgents: { await installed.detect(again: $0) },
      ticks: world.environment.ticks, media: media, tool: tool,
      sourceCache: place.root.appending(path: "source-cache"))
    let host = try await LocalHost.start(root: place.root, database: place.database, environment: environment)
    let judge = try #require(
      ProcessInfo.processInfo.environment["LOCI_EVAL_CODEX"].map { CodexJudge(codex: URL(filePath: $0)) },
      "LOCI_EVAL_CODEX is not set")
    let runner = EvalRunner(
      host: host, place: place, world: world, pages: pages, driver: driver,
      scorer: EvalScorer(scenario: .of(group), judge: judge), out: out, patience: .seconds(600))
    do {
      let outcome = try await runner.run()
      await host.close()
      if keep { try Data(place.root.path.utf8).write(to: out.appending(path: "\(group.rawValue)-data-folder.txt")) }
      return outcome
    } catch {
      await host.close()
      throw error
    }
  }
}
