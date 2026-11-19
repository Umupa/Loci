import Foundation
import LociModel
import LociStore
import Testing

@testable import LociHost

/// L-S7: once a day, late and quiet, Loci looks back on the day on its own.
@Suite(.timeLimit(.minutes(1)))
struct ReviewScenarioTests {
  static let diary = "# 2025-11-17 23:48 — 第一天\n\n聊了几句。\n\n## To remember\n- 先给结论\n"

  private static var reviewer: FakeAgent {
    FakeAgent { prompt in
      prompt.hasPrefix("It is the end of")
        ? .write(["diary/2025-11-17.md": diary], reply: "Done.") : .reply("Hello there.")
    }
  }

  private func reviewed(_ host: LocalHost, _ day: String) async throws -> ReviewOutcome? {
    let day = try #require(Day(day))
    for _ in 0..<200 {
      if let outcome = try host.database.review(of: day), outcome != .started { return outcome }
      try await Task.sleep(for: .milliseconds(20))
    }
    return try host.database.review(of: day)
  }

  private func talk(_ host: LocalHost) async throws {
    _ = try await host.run(SendMessage(to: .main, text: "Hi"))
    _ = try #require(await settled(host))
  }

  @Test func lateAndQuietTheDayIsLookedBackOnOnce() async throws {
    try await withHost(agent: Self.reviewer) { host, place, world in
      world.set(to: "22:00")
      try await talk(host)
      world.set(to: "23:20")

      world.tick()

      #expect(try await reviewed(host, "2025-11-17") == .finished)
      let page = try await host.lociPage()
      #expect(page.diaries.map(\.title) == ["第一天"])
      let prompt = try #require(world.agent.prompts.last)
      #expect(prompt.contains("notes/2025-11-17.md") && prompt.contains("diary/2025-11-17.md"))
      #expect(!prompt.contains("loci-context"))
      world.tick()
      try await Task.sleep(for: .milliseconds(100))
      #expect(world.agent.prompts.count { $0.hasPrefix("It is the end of") } == 1)
      #expect(FileManager.default.fileExists(atPath: place.root.appending(path: "agent/diary/2025-11-17.md").path()))
    }
  }

  @Test func beforeElevenNothingIsLookedBackOn() async throws {
    try await withHost(agent: Self.reviewer) { host, _, world in
      world.set(to: "21:00")
      try await talk(host)
      world.set(to: "22:59")

      world.tick()
      try await Task.sleep(for: .milliseconds(100))

      #expect(try host.database.review(of: try #require(Day("2025-11-17"))) == nil)
    }
  }

  @Test(arguments: [false, true])
  func aCheckThatCannotStartTodaysReviewSkipsTheLastMessageLookup(alreadyReviewed: Bool) throws {
    let time = alreadyReviewed ? "23:30" : "22:59"
    let now = try #require(Timestamp("2025-11-17T\(time):00.000Z"))
    let today = Day(containing: now, in: .gmt)
    let situation = DailyReview.Situation(
      now: now, timeZone: .gmt, working: false,
      lastSaid: {
        Issue.record("The check read the last message time even though today's review could not start")
        return nil
      },
      reviewed: { alreadyReviewed && $0 == today },
      active: { $0 == today })

    #expect(DailyReview.due(situation) == nil)
  }

  @Test func soSoonAfterTalkingItWaits() async throws {
    try await withHost(agent: Self.reviewer) { host, _, world in
      world.set(to: "23:15")
      try await talk(host)
      world.set(to: "23:20")

      world.tick()
      try await Task.sleep(for: .milliseconds(100))
      #expect(try host.database.review(of: try #require(Day("2025-11-17"))) == nil)

      world.set(to: "23:30")
      world.tick()
      #expect(try await reviewed(host, "2025-11-17") == .finished)
    }
  }

  @Test func whileLociIsAnsweringItWaits() async throws {
    let agent = FakeAgent { prompt in prompt.hasPrefix("It is the end of") ? .reply("Done.") : .hang }
    try await withHost(agent: agent) { host, _, world in
      world.set(to: "22:00")
      _ = try await host.run(SendMessage(to: .main, text: "Hi"))
      world.set(to: "23:30")

      world.tick()
      try await Task.sleep(for: .milliseconds(100))
      #expect(try host.database.review(of: try #require(Day("2025-11-17"))) == nil)

      _ = try await host.run(StopTurn(in: .main))
      world.advance(minutes: 10)
      world.tick()
      #expect(try await reviewed(host, "2025-11-17") == .finished)
    }
  }

  @Test func aDayMissedIsLookedBackOnTheNextDay() async throws {
    try await withHost(agent: Self.reviewer) { host, _, world in
      world.set(to: "22:00")
      try await talk(host)
      world.set(to: "09:00", daysLater: 1)

      world.tick()

      #expect(try await reviewed(host, "2025-11-17") == .finished)
    }
  }

  @Test func aDayWithNothingInItIsNotLookedBackOn() async throws {
    try await withHost(agent: Self.reviewer) { host, _, world in
      world.set(to: "23:30")

      world.tick()
      try await Task.sleep(for: .milliseconds(100))

      #expect(try host.database.review(of: try #require(Day("2025-11-17"))) == nil)
      #expect(world.agent.prompts.isEmpty)
    }
  }

  @Test func aDayWithOnlyNotesIsLookedBackOn() async throws {
    try await withHost(agent: Self.reviewer) { host, place, world in
      try place.store.writeNotes("# 2025-11-17\n- 10:00 [main] 读完 Raft\n", on: "2025-11-17")
      world.set(to: "23:30")

      world.tick()

      #expect(try await reviewed(host, "2025-11-17") == .finished)
    }
  }

  @Test func aReviewThatFailsIsNotTriedAgain() async throws {
    try await withHost { host, _, world in
      world.set(to: "22:00")
      try await talk(host)
      _ = try await host.run(SetRuntime(Runtime(provider: .grok)))
      world.set(to: "23:30")

      world.tick()

      #expect(try await reviewed(host, "2025-11-17") == .failed("grok is not installed"))
    }
  }

  @Test func lociIsWorkingWhileItLooksBack() async throws {
    let agent = FakeAgent { prompt in prompt.hasPrefix("It is the end of") ? .hang : .reply("Hi.") }
    try await withHost(agent: agent) { host, _, world in
      world.set(to: "22:00")
      try await talk(host)
      world.set(to: "23:30")
      let feed = host.subscribe(LociWorking())

      world.tick()

      #expect(await value(feed) { $0.working } != nil)
    }
  }
}
