import Foundation
import LociModel
import Synchronization
import Testing

@testable import LociHost

/// The eval itself, run against companions that behave as scripted: a careful one passes every day, one that
/// repeats itself and one that files noise fail on exactly the days they should.
@Suite(.timeLimit(.minutes(2)))
struct BackgroundEvalSelfTests {
  @Test func aCarefulCompanionPassesEveryDayOfBothGroups() async throws {
    for group in EvalScenario.Group.allCases {
      let outcome = try await Self.run(group, as: .careful)
      #expect(outcome.verdicts.count == EvalScenario.of(group).days.count)
      let failed = outcome.verdicts.filter { !$0.passed }.map { "\($0.group) \($0.day): \($0.reasons)" }
      #expect(failed.isEmpty, "\(failed)")
    }
  }

  @Test func aCompanionThatRepeatsItselfFailsEveryDayAfterTheFirst() async throws {
    let repeated = try await Self.run(.repeated, as: .repeating)
    #expect(repeated.verdicts.map(\.passed) == [true, false, false, false])
    #expect(repeated.verdicts[1].reasons.contains { $0.contains("笔记又记了「v0.9.0 发布」") })
    #expect(repeated.verdicts[2].reasons.contains { $0.contains("面板里「v0.9.0 发布」有") })

    let quiet = try await Self.run(.quiet, as: .repeating)
    #expect(quiet.verdicts.map(\.passed) == [true, false, false, true, false])
    #expect(quiet.verdicts[1].reasons.contains { $0.contains("笔记写了") })
  }

  @Test func aCompanionThatFilesNoiseFailsOnlyTheNoisyDays() async throws {
    let quiet = try await Self.run(.quiet, as: .noisy)
    #expect(quiet.verdicts.map(\.passed) == [true, true, false, true, false])
    #expect(quiet.verdicts[2].reasons.contains { $0.contains("面板多了噪音") })
    #expect(try await Self.run(.repeated, as: .noisy).verdicts.allSatisfy(\.passed))
  }

  @Test func whatTheHiddenLineIsAboutMustNotComeBackUnderAnotherLine() async throws {
    let outcome = try await Self.run(.repeated, as: .unhiding)
    #expect(outcome.verdicts.map(\.passed) == [true, true, false, false])
    #expect(outcome.verdicts[2].reasons.contains { $0.contains("不想再看的「#412") })
  }

  @Test func theReportHasALineForEachDayAndEachRunWithItsTime() async throws {
    let out = FileManager.default.temporaryDirectory.appending(path: "loci-eval-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: out) }
    let outcome = try await Self.run(.quiet, as: .careful, out: out)
    try EvalReport.write([outcome], runtime: "fake", to: out)

    let report = try String(contentsOf: out.appending(path: "report.md"), encoding: .utf8)
    #expect(report.contains("通过 5 / 5 天") && report.contains("| quiet | 3 | PASS |"))
    #expect(report.contains("| quiet | 1 | 2025-11-17 21:00 | finished |"))
    let kept = out.appending(path: "runs/quiet/day4")
    #expect(try String(contentsOf: kept.appending(path: "prompt.md"), encoding: .utf8).contains("v0.9.0 发布"))
    #expect(FileManager.default.fileExists(atPath: kept.appending(path: "record.md").path))
  }

  @Test func aJudgesAnswerIsReadWhereverTheReplyPutsIt() {
    #expect(CodexJudge.judgement(in: #"Sure: {"event": "B"}"#) == .event("B"))
    #expect(CodexJudge.judgement(in: #"{"event":"noise"}"#) == .noise)
    #expect(CodexJudge.judgement(in: "I cannot tell.") == .none)
  }

  static func run(_ group: EvalScenario.Group, as companion: ScriptedCompanion, out: URL? = nil) async throws
    -> EvalOutcome
  {
    let scenario = EvalScenario.of(group)
    let agent = Background.agent(run: companion.behavior(in: scenario))
    let place = Place()
    defer { place.remove() }
    let world = TestWorld(agent: agent)
    let pages = try await EvalPages.start()
    defer { pages.stop() }
    let counted = EvalDriver(agent)
    let host = try await LocalHost.start(
      root: place.root, database: place.database,
      environment: world.environment(
        running: { $0 == .codex ? counted : nil }, runtime: Runtime(provider: .codex)))
    let runner = EvalRunner(
      host: host, place: place, world: world, pages: pages, driver: counted,
      scorer: EvalScorer(scenario: scenario, judge: FixedJudge()), out: out, patience: patience)
    do {
      let outcome = try await runner.run()
      await host.close()
      return outcome
    } catch {
      await host.close()
      throw error
    }
  }
}

/// A companion scripted to behave one way every evening, writing the panel and its notes straight into files
/// as an agent would.
enum ScriptedCompanion {
  /// Puts each thing in the panel once, notes only what is new, and leaves noise out.
  case careful
  /// Notes everything it sees every time and adds every line again.
  case repeating
  /// Careful, except that it files noise as news.
  case noisy
  /// Careful, except that it brings back what the person hid under new words.
  case unhiding

  func behavior(in scenario: EvalScenario) -> @Sendable (String) -> FakeAgent.Behavior {
    let evenings = Mutex(0)
    return { prompt in
      let day = evenings.withLock { count in
        defer { count += 1 }
        return count
      }
      let run = prompt.firstMatch(of: /\[run\/([^\]]+)\]/).map { String($0.1) } ?? "?"
      let today = prompt.firstMatch(of: /notes\/(\d{4}-\d{2}-\d{2})\.md/).map { String($0.1) } ?? "?"
      return self.evening(day, scenario: scenario, run: run, today: today)
    }
  }

  private func evening(_ day: Int, scenario: EvalScenario, run: String, today: String) -> FakeAgent.Behavior {
    let news = scenario.news(on: day)
    let seen = scenario.known(before: day) + news
    var lines = seen.map { Self.line($0) }
    var noted = news.map(\.about)
    switch self {
    case .careful: break
    case .repeating:
      lines += (0..<day).flatMap { copy in seen.map { Self.line($0, copy: copy) } }
      noted = seen.map(\.about)
    case .noisy:
      if case .noise = scenario.days[day].kind {
        lines.append(PanelListItem(title: "Fix typo in README", link: URL(string: "https://github.com/x/y/commit/1")))
        noted = ["Fix typo in README"]
      }
    case .unhiding:
      if let hidden = scenario.hidden(by: day) {
        lines.append(PanelListItem(title: "又看到 \(hidden.keywords[0]) 有新评论", link: URL(string: "https://x.y/again")))
      }
    }
    if noted.isEmpty { noted = ["没有新东西。"] }
    let panel = Panel(
      name: EvalRunner.panel, title: "CubeSandbox", follow: "CubeSandbox",
      body: .rows([.sentence("CubeSandbox 最近 \(seen.count) 件事。"), .list(lines)]))
    let notes = "# \(today)\n\n" + noted.map { "- 21:01 [run/\(run)] \($0)\n" }.joined()
    let json = (try? Prompts.json(panel)) ?? ""
    return .write(
      ["notes/\(today).md": notes, "panels/\(EvalRunner.panel).json": json],
      reply: "看完了。\(noted.joined(separator: "；"))")
  }

  private static func line(_ event: EvalEvent, copy: Int? = nil) -> PanelListItem {
    let id = event.id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? event.id
    let suffix = copy.map { "/\($0)" } ?? ""
    return PanelListItem(
      title: event.about, link: URL(string: "https://github.com/TencentCloud/CubeSandbox/e/\(id)\(suffix)"))
  }
}
