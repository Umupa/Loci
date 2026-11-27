import Foundation
import LociModel
import LociStore
import Testing

@testable import LociHost

/// L-S25, M-S15: a run in the background runs on the conversation it belongs to, or, refreshing panels, on the
/// tool model; with no tool model on the main conversation's runtime.
@Suite(.timeLimit(.minutes(1)))
struct BackgroundRuntimeTests {
  @Test func aFollowUpRunsOnTheConversationThatSetIt() async throws {
    try await withHost(agent: FollowUpTellingTests.agent) { host, _, world in
      let item = ConversationRef.item(try await host.run(AddTextItem(fileName: "raft.md", text: "# Raft\n")).id)
      _ = try await host.run(SetConversationRuntime(Runtime(provider: .codex, model: "main-model"), for: .main))
      _ = try await host.run(SetConversationRuntime(Runtime(provider: .codex, model: "reading-model"), for: item))
      _ = await Background.call(AddFollowUp(.after(minutes: 2), "看 Raft"), from: .conversation(item), on: host)

      world.advance(minutes: 2)
      world.tick()
      for _ in 0..<500 where FollowUpTellingTests.told(item, on: host).isEmpty {
        try await Task.sleep(for: .milliseconds(10))
      }

      #expect(FollowUpTellingTests.told(item, on: host) == ["看过了：看 Raft。"])
      #expect(world.agent.opened.map(\.model) == ["reading-model"])
    }
  }

  @Test func withoutAToolModelAPanelRefreshRunsOnTheMainConversation() async throws {
    let agent = FakeAgent(provider: .codex) { prompt in
      prompt.hasPrefix("Refresh the panel")
        ? .write(["panels/radar.json": PanelRefreshScenarioTests.refreshed], reply: "Saved.") : .reply("Hello there.")
    }
    try await withHost(agent: agent) { host, _, world in
      let item = ConversationRef.item(try await host.run(AddTextItem(fileName: "raft.md", text: "# Raft\n")).id)
      _ = try await host.run(SetConversationRuntime(Runtime(provider: .codex, model: "main-model"), for: .main))
      _ = try await host.run(SetConversationRuntime(Runtime(provider: .codex, model: "reading-model"), for: item))
      _ = try await host.run(SavePanel(PanelScenarioTests.radar))

      _ = try await host.run(RefreshPanel(PanelRef("radar")))
      _ = try await Background.runSession(world)

      #expect(world.agent.opened.map(\.model) == ["main-model"])
    }
  }
}
