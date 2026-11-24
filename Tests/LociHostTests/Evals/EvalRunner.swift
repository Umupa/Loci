import Foundation
import LociModel
import LociStore
import Testing

@testable import LociHost

/// One run of an eval day as the report shows it.
struct EvalRun: Sendable, Codable {
  let group: String
  let day: Int
  /// The app's clock when the run started.
  let at: String
  let run: String?
  let outcome: String
  let summary: String?
  let cost: EvalCost?
}

/// What a scenario came to: a verdict and a run for each day.
struct EvalOutcome: Sendable, Codable {
  let verdicts: [EvalVerdict]
  let runs: [EvalRun]
}

/// Follows a scenario's schedule for its days on a host: each evening it sets the pages, moves the clock to
/// 21:00, lets the scheduler raise the run, waits for it, and scores what it left behind.
struct EvalRunner {
  let host: LocalHost
  let place: Place
  let world: TestWorld
  let pages: EvalPages
  let driver: EvalDriver
  let scorer: EvalScorer
  /// Where each day's panel, notes and run record are copied; `nil` keeps nothing.
  let out: URL?
  /// How long one run may take before the day fails.
  let patience: Duration

  static let panel = "cubesandbox"
  static let schedule = "cubesandbox-news"

  private var scenario: EvalScenario { scorer.scenario }

  func run() async throws -> EvalOutcome {
    _ = try await host.run(
      SavePanel(
        Panel(
          name: Self.panel, title: "CubeSandbox", sources: ["127.0.0.1"], follow: follow,
          body: .rows([.sentence("还没有看过。")]))))
    let entry = try await Background.add(
      Self.schedule,
      ScheduleDraft(
        title: "CubeSandbox 的动态", follow: follow, every: .day(at: try Background.clock("21:00")),
        destination: .panel(Self.panel)), on: host)
    var verdicts: [EvalVerdict] = []
    var runs: [EvalRun] = []
    var before = EvalSnapshot.empty
    var hiddenKey: String?
    for (index, day) in scenario.days.enumerated() {
      pages.show(day.pages.pages)
      if let hide = day.hide.flatMap(scenario.event) { hiddenKey = try await self.hide(hide) ?? hiddenKey }
      world.set(to: "21:00", daysLater: index == 0 ? 0 : 1)
      world.tick()
      let done = await value(host.subscribe(WatchScheduleRuns(entry.ref)), within: patience) { runs in
        runs.count == index + 1 && Background.finished(runs)
      }
      guard let latest = done?.first else {
        verdicts.append(
          EvalVerdict(group: scenario.group.rawValue, day: index + 1, passed: false, reasons: ["run 没有在时限内结束"]))
        runs.append(record(day: index, run: nil))
        break
      }
      let after = try await snapshot(of: latest.id)
      verdicts.append(await scorer.score(day: index, before: before, after: after, hiddenKey: hiddenKey))
      runs.append(record(day: index, run: latest))
      try keep(day: index, run: latest)
      before = after
    }
    return EvalOutcome(verdicts: verdicts, runs: runs)
  }

  private var follow: String {
    "看看 CubeSandbox 的 release、issue 和提交有没有新东西：\(pages.url("/releases"))、\(pages.url("/issues"))、"
      + "\(pages.url("/commits"))"
  }

  /// Marks the panel's list line about `event` 「不想再看」 the way the panel does; its key, or `nil` when no
  /// list line is about it.
  private func hide(_ event: EvalEvent) async throws -> String? {
    guard case .rows(let rows)? = place.store.panel(named: Self.panel)?.panel?.body else { return nil }
    for case .list(let lines) in rows {
      guard let line = lines.first(where: { event.isMentioned(in: $0.title + " " + ($0.subtitle ?? "")) }) else {
        continue
      }
      _ = try await host.run(MarkPanelLine(Self.panel, PanelLineKey(line), PanelLineMark(hidden: true)))
      return PanelLineKey(line).rawValue
    }
    return nil
  }

  private func snapshot(of run: Run.ID) async throws -> EvalSnapshot {
    let today = Day(containing: world.now, in: TestWorld.timeZone)
    return EvalSnapshot(
      entries: EvalSnapshot.entries(of: place.store.panel(named: Self.panel)?.panel),
      notes: EvalSnapshot.notes(try place.store.dayNotes(of: today), of: run),
      mainMessages: try await host.conversation(.main).messages.count)
  }

  private func record(day: Int, run: Run?) -> EvalRun {
    let clock =
      "\(Day(containing: world.now, in: TestWorld.timeZone)) \(TimeOfDay(of: world.now, in: TestWorld.timeZone))"
    let outcome: String
    let summary: String?
    switch run?.outcome {
    case .finished(let said, _)?: (outcome, summary) = ("finished", said)
    case .failed(let reason, let tries)?: (outcome, summary) = ("failed after \(tries): \(reason)", nil)
    case .running?, nil: (outcome, summary) = ("did not finish", nil)
    }
    return EvalRun(
      group: scenario.group.rawValue, day: day + 1, at: clock, run: run?.id.description, outcome: outcome,
      summary: summary, cost: run.flatMap { driver.cost(of: LocalSession.run($0.id).tag) })
  }

  /// Copies the day's run record, panel, notes and prompt next to the report.
  private func keep(day: Int, run: Run) throws {
    guard let out else { return }
    let folder = out.appending(path: "runs/\(scenario.group.rawValue)/day\(day + 1)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let store = place.store
    let today = Day(containing: world.now, in: TestWorld.timeZone)
    let files: [(String, String?)] = [
      ("record.md", try store.runRecord(at: run.record)),
      ("notes.md", try store.dayNotes(of: today)),
      ("panel.json", try place.store.panel(named: Self.panel)?.panel.map(Prompts.json)),
      ("prompt.md", driver.cost(of: LocalSession.run(run.id).tag)?.prompt),
    ]
    for case (let name, let text?) in files { try Data(text.utf8).write(to: folder.appending(path: name)) }
  }
}
