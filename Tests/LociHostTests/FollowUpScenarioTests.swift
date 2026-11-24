import Foundation
import LociModel
import LociStore
import Testing

@testable import LociHost

/// WK-S4, WK-S6: follow-ups the companion sets for itself, and what the main conversation is told of runs.
@Suite(.timeLimit(.minutes(1)))
struct FollowUpScenarioTests {
  static let what = "看看 https://github.com/x/y/issues/244 有没有回复"

  /// Sets a follow-up the way the companion does, with `loci followup` in the main conversation.
  private func set(_ time: FollowUpTime, on host: LocalHost) async throws -> FollowUp {
    let reply = await Background.call(AddFollowUp(time, Self.what), from: .conversation(.main), on: host)
    guard case .value(let data)? = reply else { throw HostError.invalidRequest("\(String(describing: reply))") }
    return try JSONDecoder().decode(FollowUp.self, from: data)
  }

  /// The prompt of the latest message in the main conversation, as the companion was sent it.
  private func said(_ world: TestWorld) -> String {
    world.agent.prompts.last { $0.contains("<loci-context>") } ?? ""
  }

  @Test func aFollowUpRunsOnceAtItsTimeAndLeavesTheList() async throws {
    let agent = Background.agent { _ in .reply("看了。#244 有人回了，说下个版本修。") }
    try await withHost(agent: agent) { host, _, world in
      let followUp = try await set(.after(minutes: 60), on: host)
      #expect(followUp.conversation == .main)
      #expect(try await host.timers().followUps == [followUp])
      #expect(try await host.timers().next == followUp.due)

      world.advance(minutes: 60)
      world.tick()
      _ = await value(host.subscribe(WatchTimers())) { $0.followUps.isEmpty }
      world.tick()
      try await Background.quiet()

      let prompts = Background.prompts(world, starting: Background.followUp)
      #expect(prompts.count == 1)
      #expect(prompts.first?.contains(Self.what) == true)
    }
  }

  @Test func theNextMainTurnIsToldWhatCameOfTheFollowUpOnce() async throws {
    let agent = Background.agent { _ in .reply("看了。#244 有人回了，说下个版本修。") }
    try await withHost(agent: agent) { host, _, world in
      _ = try await set(.after(minutes: 30), on: host)
      world.advance(minutes: 30)
      world.tick()
      #expect(try await Background.ran(1, starting: Background.followUp, on: host, world))

      _ = try await host.run(SendMessage(to: .main, text: "在吗"))
      _ = await settled(host)
      let first = said(world)
      _ = try await host.run(SendMessage(to: .main, text: "还在吗"))
      _ = await settled(host, prompts: 2)
      let second = said(world)

      #expect(first.contains("Follow-ups you set came due") && first.contains(Self.what))
      #expect(first.contains("#244 有人回了，说下个版本修。") && first.contains("runs/"))
      #expect(!second.contains("Follow-ups you set came due"))
    }
  }

  @Test func aFollowUpThatCouldNotBeDoneIsToldAsNotDone() async throws {
    try await withHost(agent: Background.agent { _ in .fail("rate limited") }) { host, _, world in
      _ = try await set(.after(minutes: 30), on: host)
      world.advance(minutes: 30)
      for (tries, wait) in [(1, 0), (2, 1), (3, 5)] as [(Int, Int64)] {
        world.advance(minutes: wait)
        world.tick()
        #expect(try await Background.ran(tries, starting: Background.followUp, on: host, world))
      }
      world.advance(minutes: 15)
      world.tick()
      try await Background.quiet()
      #expect(Background.prompts(world, starting: Background.followUp).count == 3)

      _ = try await host.run(SendMessage(to: .main, text: "在吗"))
      _ = await settled(host)

      #expect(said(world).contains("not done; it failed 3 time(s)"))
    }
  }

  @Test func aCancelledFollowUpNeverRuns() async throws {
    try await withHost(agent: Background.agent { _ in .reply("看了。") }) { host, _, world in
      let followUp = try await set(.after(minutes: 30), on: host)

      let cancelled = await Background.call(CancelFollowUp(followUp.id), from: .conversation(.main), on: host)
      world.advance(minutes: 30)
      world.tick()
      try await Background.quiet()

      #expect(cancelled == .value(try JSONEncoder().encode(Done())))
      #expect(try await host.timers().followUps.isEmpty)
      #expect(Background.prompts(world, starting: Background.followUp).isEmpty)
    }
  }

  @Test func theMainConversationIsToldWhatSchedulesFoundSinceItLastTalked() async throws {
    let agent = Background.agent { _ in .reply("看了。CubeSandbox 发了 v0.9.0。") }
    try await withHost(agent: agent) { host, _, world in
      _ = try await host.run(SendMessage(to: .main, text: "早"))
      _ = await settled(host)
      let entry = try await Background.add("sandbox-news", Background.draft(.hour), on: host)
      world.advance(minutes: 60)
      world.tick()
      let runs = try #require(await Background.runs(of: entry.ref, on: host, where: Background.finished))

      _ = try await host.run(SendMessage(to: .main, text: "CubeSandbox 最近怎样"))
      _ = await settled(host, prompts: 2)

      let prompt = said(world)
      #expect(prompt.contains("Done in the background since we last talked"))
      #expect(prompt.contains("sandbox-news: CubeSandbox 发了 v0.9.0。 (\(runs[0].record))"))
    }
  }
}
