import Foundation
import LociModel
import LociStore

@testable import LociHost

/// Plays a memory scenario on a host: each day the person says their lines in the main conversation in the
/// evening, the day is looked back on at 23:30, and on the morning after the last day the questions are asked.
/// Then it grades the answers and measures what was remembered.
struct MemoryEvalRunner {
  let host: LocalHost
  let place: Place
  let world: TestWorld
  let scenario: MemoryScenario
  let judge: (any MemoryJudge)?
  /// How long one turn or one review may take before the eval gives up on it.
  let patience: Duration

  func run() async throws -> MemoryOutcome {
    var problems: [String] = []
    var turnTokens: [Int] = []
    var typed = 0
    for (index, lines) in scenario.days.enumerated() {
      world.set(to: "20:00", daysLater: index == 0 ? 0 : 1)
      for line in lines {
        typed += 1
        guard try await say(line, typed: typed) != nil else {
          problems.append("第 \(index + 1) 天「\(line)」没有在时限内答完")
          continue
        }
        if let used = await host.loci.existingRun(of: .main)?.snapshot.context?.used { turnTokens.append(used) }
      }
      world.set(to: "23:30")
      world.tick()
      if try await !reviewed(Day(containing: world.now, in: TestWorld.timeZone)) {
        problems.append("第 \(index + 1) 天的回顾没有在时限内结束")
      }
    }
    world.set(to: "10:00", daysLater: 1)
    var answers: [MemoryOutcome.Answer] = []
    for question in scenario.questions {
      typed += 1
      let answer = try await say(question.ask, typed: typed) ?? ""
      if let used = await host.loci.existingRun(of: .main)?.snapshot.context?.used { turnTokens.append(used) }
      var reasons = MemoryBudget.words(question, in: answer)
      if await judge?.grade(question, answer: answer) == false { reasons.append("判分模型认为没有答出「\(question.fact)」") }
      answers.append(
        MemoryOutcome.Answer(question: question.ask, answer: answer, passed: reasons.isEmpty, reasons: reasons))
    }
    return MemoryOutcome(answers: answers, cost: try await cost(turnTokens: turnTokens), problems: problems)
  }

  /// Says `text` in the main conversation and gives the reply, or `nil` when no reply came in time.
  private func say(_ text: String, typed: Int) async throws -> String? {
    _ = try await host.run(SendMessage(to: .main, text: text))
    let settled = await value(host.subscribe(OneConversation(.main)), within: patience) { conversation in
      conversation.turn == nil && conversation.messages.count { $0.isTyped } == typed
    }
    guard let messages = settled?.messages else { return nil }
    let turn = messages.suffix(from: messages.lastIndex { $0.isTyped } ?? messages.startIndex)
    return turn.compactMap { if case .reply(let words) = $0.body { words } else { nil } }.joined()
  }

  /// Waits for the day's review to end and the worker to be free.
  private func reviewed(_ day: Day) async throws -> Bool {
    let deadline = ContinuousClock.now + patience
    while ContinuousClock.now < deadline {
      if let outcome = try host.database.review(of: day), outcome != .started,
        await host.worker.status == nil
      {
        return true
      }
      try await Task.sleep(for: .milliseconds(200))
    }
    return false
  }

  private func cost(turnTokens: [Int]) async throws -> MemoryOutcome.Cost {
    let store = place.store
    let index = try store.agentText(.memory)
    let pages = store.home(.chat).wikiPages().map { (try? store.home(.chat).wikiPage($0)) ?? "" }
    let agents = (try? String(contentsOf: store.agentFolder.appending(path: "AGENTS.md"), encoding: .utf8)) ?? ""
    let reviews = try host.database.runs(startedAfter: Timestamp(millisecondsSince1970: 0)).filter { run in
      if case .review = run.kind { true } else { false }
    }
    let reviewTokens = reviews.compactMap(\.usage?.used)
    let lines = index.split(separator: "\n", omittingEmptySubsequences: true).count
    let wiki = pages.reduce(0) { $0 + $1.count }
    return MemoryOutcome.Cost(
      indexLines: lines, indexCharacters: index.count, wikiPages: pages.count, wikiCharacters: wiki,
      agentsCharacters: agents.count, reviewTokens: reviewTokens, turnTokens: turnTokens,
      checks: MemoryBudget.checks(
        indexLines: lines, indexCharacters: index.count, wikiCharacters: wiki, agentsCharacters: agents.count,
        tokens: reviewTokens + turnTokens))
  }
}
