import Foundation
import LociModel
import LociStore
import Testing

@testable import LociHost

/// WT-S11: declining or starting a card is feedback its home's daily review reads, writes into `WATCH.md` and
/// then forgets; a day with only feedback is still looked back on, and a review that fails keeps it.
@Suite(.timeLimit(.minutes(1)))
struct WatchFeedbackTests {
  static let reviewStart = "It is the end of"

  static func review(_ host: LocalHost, _ day: String) async throws -> ReviewOutcome? {
    let day = try #require(Day(day))
    for _ in 0..<500 {
      if let outcome = try host.database.review(of: day), outcome != .started {
        await host.worker.quiet(.chat)
        return outcome
      }
      try await Task.sleep(for: .milliseconds(20))
    }
    return nil
  }

  static func card(_ what: String, on host: LocalHost) async throws -> NextUp {
    try await NextUpScenarioTests.add(what, on: host)
  }

  @Test func aDeclinedCardIsNoiseAndAStartedOneUsefulForThatDaysReview() async throws {
    let agent = FakeAgent(provider: .codex) { prompt in
      prompt.hasPrefix(Self.reviewStart) ? .write(["WATCH.md": "- 噪音：龙虎榜\n"], reply: "Done.") : .reply("好")
    }
    try await withHost(agent: agent) { host, place, world in
      world.set(to: "21:00")
      let noise = try await Self.card("龙虎榜：游资抢筹", on: host)
      let useful = try await Self.card("国常会稳市", on: host)
      _ = try await host.setNextUp(SetNextUp(noise.id, .decline, version: noise.version))
      _ = try await host.run(StartNextUp(useful.id, version: useful.version))
      _ = try #require(await settled(host))
      world.set(to: "23:30")
      world.tick()

      #expect(try await Self.review(host, "2025-11-17") == .finished)
      let prompt = try #require(Background.prompts(world, starting: Self.reviewStart).first)
      #expect(prompt.contains("declined: 龙虎榜：游资抢筹"))
      #expect(prompt.contains("started: 国常会稳市"))
      #expect(prompt.contains("WATCH.md"))
      #expect(try host.database.allNextUps().allSatisfy { $0.feedback == nil })
      #expect(try place.store.home(.chat).watch() == "- 噪音：龙虎榜\n")
    }
  }

  @Test func aDayWithOnlyADeclinedCardIsLookedBackOn() async throws {
    try await withHost(agent: FakeAgent(provider: .codex)) { host, _, world in
      let card = try await Self.card("个股异动", on: host)
      _ = try await host.setNextUp(SetNextUp(card.id, .decline, version: card.version))
      world.set(to: "23:30")
      world.tick()

      #expect(try await Self.review(host, "2025-11-17") == .finished)
    }
  }

  @Test func aReviewThatFailsKeepsTheFeedback() async throws {
    try await withHost(agent: FakeAgent(provider: .codex)) { host, _, world in
      let card = try await Self.card("个股异动", on: host)
      _ = try await host.setNextUp(SetNextUp(card.id, .decline, version: card.version))
      _ = try await host.run(SetConversationRuntime(Runtime(provider: .grok), for: .main))
      world.set(to: "23:30")
      world.tick()

      #expect(try await Self.review(host, "2025-11-17") != .finished)
      #expect(try host.database.nextUp(card.id)?.feedback?.map(\.kind) == [.declined])
    }
  }

  @Test func aProjectsFeedbackIsReadOnlyByItsOwnReview() async throws {
    try await withHost(agent: FakeAgent(provider: .codex)) { host, _, world in
      let project = try await ProjectScenarioTests.start(host)
      let card = try await NextUpScenarioTests.add(
        "QDII 溢价", in: .conversation(.project(project)), on: host)
      _ = try await host.setNextUp(SetNextUp(card.id, .decline, version: card.version))
      let day = Day(containing: world.now, in: TestWorld.timeZone)
      let cards = try host.database.allNextUps()

      let own = ReviewBrief.make(
        for: day, in: .project(project), store: host.store, timeZone: TestWorld.timeZone, cards: cards)
      let chat = ReviewBrief.make(for: day, in: .chat, store: host.store, timeZone: TestWorld.timeZone, cards: cards)
      #expect(own.feedback.map(\.what) == ["QDII 溢价"])
      #expect(chat.feedback.isEmpty)
    }
  }
}
