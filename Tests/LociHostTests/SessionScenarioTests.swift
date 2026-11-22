import Foundation
import LociModel
import Testing

@testable import LociHost

/// L-S3: the main conversation stays one conversation while the agent sessions under it are renewed.
@Suite(.timeLimit(.minutes(1)))
struct SessionScenarioTests {
  private func say(_ text: String, to host: LocalHost, prompts: Int) async throws {
    _ = try await host.run(SendMessage(to: .main, text: text))
    _ = try #require(await settled(host, prompts: prompts))
  }

  @Test func theSameSessionGoesOnWhileNothingChanges() async throws {
    try await withHost { host, _, world in
      try await say("one", to: host, prompts: 1)
      try await say("two", to: host, prompts: 2)

      #expect(world.agent.opened.count == 1)
    }
  }

  @Test func aNewRuntimeTakesOverAtTheNextTurnAndIsToldWhereWeLeftOff() async throws {
    try await withHost { host, _, world in
      try await say("Remember the word cobalt", to: host, prompts: 1)

      _ = try await host.run(SetRuntime(Runtime(provider: .pi, model: "other-model")))
      try await say("What was the word?", to: host, prompts: 2)

      #expect(world.agent.opened.map(\.model) == [nil, "other-model"])
      #expect(world.agent.opened.last?.resume == nil)
      let recap = try #require(world.agent.prompts.last)
      #expect(recap.contains("Person: Remember the word cobalt"))
      #expect(recap.contains("Companion: Hello there."))
      #expect(recap.hasSuffix("What was the word?"))
      let conversation = try await host.conversation(.main)
      #expect(!conversation.messages.contains { $0.body == .startedOver })
    }
  }

  @Test func aTurnAlreadyRunningFinishesOnTheRuntimeItBegan() async throws {
    try await withManualHost { host, _, _, agent in
      _ = try await host.run(SendMessage(to: .main, text: "Hi"))
      #expect(await working(host))
      let session = try #require(await agent.sessions.first)

      _ = try await host.run(SetRuntime(Runtime(provider: .pi, model: "other-model")))
      await session.finish()

      #expect(await settled(host)?.bodies.last == .reply("Waiting"))
      #expect(await agent.opened.count == 1)
    }
  }

  @Test func rewritingTheSoulRenewsTheSession() async throws {
    try await withHost { host, place, world in
      try await say("one", to: host, prompts: 1)

      _ = try await host.run(SaveSoul(core: "You are Loci, and you speak in haiku."))
      try await say("two", to: host, prompts: 2)

      #expect(world.agent.opened.count == 2)
      let instructions = try String(contentsOf: place.root.appending(path: "agent/AGENTS.md"), encoding: .utf8)
      #expect(instructions.contains("you speak in haiku"))
    }
  }

  @Test func theNextTurnUsesTheNewCompanionNameAndKeepsTheConversation() async throws {
    try await withHost { host, place, world in
      try await say("one", to: host, prompts: 1)
      _ = try await host.run(RenameCompanion("Jun"))
      try await say("two", to: host, prompts: 2)
      let file = place.root.appending(path: "agent/AGENTS.md")
      #expect(try String(contentsOf: file, encoding: .utf8).contains("Your current name is Jun."))
      #expect(world.agent.prompts.last?.contains("Person: one") == true)
      _ = try await host.run(RenameCompanion(""))
      try await say("three", to: host, prompts: 3)
      let instructions = try String(contentsOf: file, encoding: .utf8)
      #expect(instructions.contains("You have no name yet."))
      #expect(!instructions.contains("Your current name is Jun."))
    }
  }

  @Test func whatLociLearnsAboutThePersonRenewsTheSession() async throws {
    try await withHost { host, place, world in
      try await say("one", to: host, prompts: 1)

      try place.edit(place.root.appending(path: "agent/USER.md")) { $0 + "- 2025-11-17 叫我小王\n" }
      try await say("two", to: host, prompts: 2)

      #expect(world.agent.opened.count == 2)
    }
  }

  @Test func aSessionThreeQuartersFullIsRenewed() async throws {
    let agent = FakeAgent { prompt in
      prompt.typed.hasSuffix("one")
        ? .report(ContextUsage(used: 150_000, window: 200_000), reply: "Full.") : .reply("Ok.")
    }
    try await withHost(agent: agent) { host, _, _ in
      try await say("one", to: host, prompts: 1)
      try await say("two", to: host, prompts: 2)

      #expect(agent.opened.count == 2)
      #expect(agent.prompts.last?.contains("Companion: Full.") == true)
    }
  }

  @Test func aSessionWithRoomLeftGoesOn() async throws {
    let agent = FakeAgent { _ in .report(ContextUsage(used: 100_000, window: 200_000), reply: "Ok.") }
    try await withHost(agent: agent) { host, _, _ in
      try await say("one", to: host, prompts: 1)
      try await say("two", to: host, prompts: 2)

      #expect(agent.opened.count == 1)
    }
  }

  @Test func aSessionThatCompactedItselfIsRenewed() async throws {
    let agent = FakeAgent { prompt in prompt.typed.hasSuffix("one") ? .compact(reply: "Squeezed.") : .reply("Ok.") }
    try await withHost(agent: agent) { host, _, _ in
      try await say("one", to: host, prompts: 1)
      try await say("two", to: host, prompts: 2)

      #expect(agent.opened.count == 2)
    }
  }

  @Test func withoutAReportTheSessionIsRenewedOnceItHasSaidEnough() async throws {
    let long = String(repeating: "调度", count: SessionRotation.fullTokens * SessionRotation.charactersPerToken / 2)
    let agent = FakeAgent { prompt in prompt.typed.hasSuffix("one") ? .reply(long) : .reply("Ok.") }
    try await withHost(agent: agent) { host, _, _ in
      try await say("one", to: host, prompts: 1)
      try await say("two", to: host, prompts: 2)

      #expect(agent.opened.count == 2)
    }
  }
}
