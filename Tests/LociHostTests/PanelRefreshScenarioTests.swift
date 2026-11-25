import Foundation
import LociModel
import LociStore
import Testing

@testable import LociHost

/// P-S8: panels are refreshed in the background, one at a time, by a Loci the main conversation never shows.
@Suite(.timeLimit(.minutes(1)))
struct PanelRefreshScenarioTests {
  static let refreshed = """
    { "title": "沙箱快讯", "follow": "盯着 CubeSandbox 的新版本", "refresh": { "every": "day", "at": "10:00" },
      "rows": [{ "row": "sentence", "text": "**v0.9.0** 发布。" }] }
    """

  /// Rewrites the panel when asked to refresh it; in the main conversation, says hello or keeps working.
  static func agent(
    refreshing behavior: FakeAgent.Behavior = .write(["panels/radar.json": refreshed], reply: "Saved."),
    main: FakeAgent.Behavior = .reply("Hello there.")
  )
    -> FakeAgent
  {
    FakeAgent { prompt in prompt.hasPrefix("Refresh the panel") ? behavior : main }
  }

  static func refreshPrompts(_ world: TestWorld) -> Int {
    world.agent.prompts.count { $0.hasPrefix("Refresh the panel") }
  }

  private func title(_ host: LocalHost, becomes title: String) async -> Bool {
    await value(host.subscribe(WatchPanelColumn())) { column in
      column.refreshing.isEmpty
        && column.slots.contains { slot in
          if case .panel(let panel) = slot { panel.title == title } else { false }
        }
    } != nil
  }

  private func quiet() async throws {
    try await Task.sleep(for: .milliseconds(150))
  }

  @Test func aPanelIsRefreshedOnceItsTimeComesAndTheMainConversationNeverSeesIt() async throws {
    try await withHost(agent: Self.agent()) { host, _, world in
      _ = try await host.run(SavePanel(PanelScenarioTests.radar))
      world.set(to: "09:59")
      world.tick()
      try await quiet()
      #expect(Self.refreshPrompts(world) == 0)

      world.set(to: "10:00")
      world.tick()

      #expect(await title(host, becomes: "沙箱快讯"))
      let prompt = try #require(world.agent.prompts.last)
      #expect(prompt.contains("It follows: 盯着 CubeSandbox 的新版本"))
      #expect(prompt.contains(#""title" : "沙箱雷达""#) && prompt.contains("panel save radar"))
      world.tick()
      try await quiet()
      #expect(Self.refreshPrompts(world) == 1)
      #expect(try await host.conversation(.main).messages.isEmpty)
    }
  }

  @Test func aTimeMissedWhileTheAppWasClosedIsMadeUpWhenItOpens() async throws {
    try await withHost(agent: Self.agent()) { host, place, world in
      try place.store.home(.chat).savePanel(PanelScenarioTests.radar)
      let threeDaysAgo = Timestamp(millisecondsSince1970: world.now.millisecondsSince1970 - 3 * 24 * 3_600_000)
      try place.store.home(.chat).changePanelState { $0.refreshed["radar"] = threeDaysAgo }

      world.tick()

      #expect(await title(host, becomes: "沙箱快讯"))
      world.tick()
      try await quiet()
      #expect(Self.refreshPrompts(world) == 1)
    }
  }

  @Test func aDuePanelWaitsWhileLociIsAnswering() async throws {
    try await withHost(agent: Self.agent(main: .hang)) { host, _, world in
      _ = try await host.run(SavePanel(PanelScenarioTests.radar))
      _ = try await host.run(SendMessage(to: .main, text: "Hi"))
      world.set(to: "10:00")

      world.tick()
      try await quiet()
      #expect(Self.refreshPrompts(world) == 0)

      _ = try await host.run(StopTurn(in: .main))
      world.tick()
      #expect(await title(host, becomes: "沙箱快讯"))
    }
  }

  @Test func askingToRefreshStartsAtOnceWhetherDueOrNot() async throws {
    try await withHost(agent: Self.agent()) { host, _, world in
      _ = try await host.run(SavePanel(PanelScenarioTests.radar))

      _ = try await host.run(RefreshPanel(PanelRef("radar")))

      #expect(await title(host, becomes: "沙箱快讯"))
      await #expect(throws: HostError.notFound("nothing")) { _ = try await host.run(RefreshPanel(PanelRef("nothing"))) }
      #expect(Self.refreshPrompts(world) == 1)
    }
  }

  @Test func aRefreshThatWritesNothingLeavesThePanelAndIsNotRetriedAtOnce() async throws {
    try await withHost(agent: Self.agent(refreshing: .reply("Could not reach GitHub."))) { host, _, world in
      _ = try await host.run(SavePanel(PanelScenarioTests.radar))
      world.set(to: "10:00")

      world.tick()
      #expect(await title(host, becomes: "沙箱雷达"))
      try await quiet()
      world.tick()
      try await quiet()

      #expect(Self.refreshPrompts(world) == 1)
      #expect(try await host.panelColumn(of: .chat).slots == [.panel(PanelScenarioTests.radar)])
    }
  }

  @Test func oneRefreshRunsAtATimeAndTheColumnSaysWhich() async throws {
    try await withHost(agent: Self.agent(refreshing: .hang)) { host, _, world in
      _ = try await host.run(SavePanel(PanelScenarioTests.radar))
      _ = try await host.run(SavePanel(PanelScenarioTests.panel("other")))

      _ = try await host.run(RefreshPanel(PanelRef("radar")))
      _ = try await host.run(RefreshPanel(PanelRef("other")))

      let column = await value(host.subscribe(WatchPanelColumn())) { !$0.refreshing.isEmpty }
      #expect(column?.refreshing == ["radar"])
      try await quiet()
      #expect(Self.refreshPrompts(world) == 1)
    }
  }
}
