import Foundation
import LociModel
import LociStore
import Testing

@testable import LociHost

/// DS-S7: a panel that follows a source's entries wakes the companion only for new ones the rules let
/// through; the companion names the ids it keeps, and the app fills in each one's own link and time.
@Suite(.timeLimit(.minutes(1)))
struct FeedScenarioTests {
  static let pick = "Pick for the panel"
  static let news = DataSource(
    name: "news", title: "快讯", every: SourceEvery(minutes: 1)!, script: "function requests() {}")
  static let panel = Panel(
    name: "flash", title: "快讯", follow: "和纳指、港股有关的快讯", feed: PanelFeed(source: "news", skip: ["广告"]),
    body: .rows([.sentence("还没有新快讯。")]))

  static func entry(_ id: String, _ title: String) -> SourceEntry {
    SourceEntry(
      id: id, title: title, url: URL(string: "https://news.example/\(id)"),
      at: Timestamp(millisecondsSince1970: TestWorld.instant.millisecondsSince1970 - 600_000), note: "+1.2%")
  }

  static let first = [entry("a1", "纳指期货走高"), entry("a2", "某券商开户广告")]

  static func agent(picking: FakeAgent.Behavior = .hang) -> FakeAgent {
    FakeAgent(provider: .codex) { prompt in prompt.hasPrefix(pick) ? picking : .reply("好的。") }
  }

  /// A host with the source saved before the panel that follows it, as the companion makes them.
  static func withFeed(
    _ agent: FakeAgent = agent(), _ body: (LocalHost, TestWorld, FakeSources) async throws -> Void
  ) async throws {
    let runner = FakeSources()
    try await withHost(agent: agent, sources: runner) { host, _, world in
      _ = try await host.run(SaveDataSource(Self.news))
      _ = try await host.run(SavePanel(Self.panel))
      try await body(host, world, runner)
    }
  }

  static func pickPrompts(_ world: TestWorld) -> [String] { Background.prompts(world, starting: pick) }

  @Test func aPanelThatFollowsEntriesIsWokenOnlyByNewOnesTheRulesLetThrough() async throws {
    try await Self.withFeed { host, world, runner in
      runner.set(entries: [Self.entry("b1", "某平台广告")])
      await RepairScenarioTests.fetch(1, on: host, world)
      #expect(try host.database.openEvents().isEmpty)

      runner.set(entries: Self.first)
      await RepairScenarioTests.fetch(1, on: host, world)
      let raised = try host.database.openEvents().map(\.source)
      #expect(raised == [.panel(PanelRef("flash"), asked: false)])

      world.tick()
      let prompt = try #require(await Self.firstPick(world))
      #expect(prompt.contains("<external-content") && prompt.contains("[a1] 纳指期货走高 — +1.2%"))
      #expect(!prompt.contains("广告"))
      #expect(prompt.contains("panel pick flash"))
    }
  }

  @Test func noNewEntriesWakeNothing() async throws {
    try await Self.withFeed(Self.agent(picking: .reply("没有要留的。"))) { host, world, runner in
      runner.set(entries: Self.first)
      await RepairScenarioTests.fetch(1, on: host, world)
      world.tick()
      #expect(try await Background.ran(1, starting: Self.pick, on: host, world))

      await RepairScenarioTests.fetch(2, on: host, world)
      world.tick()
      try await Background.quiet()

      #expect(Self.pickPrompts(world).count == 1)
      #expect(try host.database.openEvents().isEmpty)
    }
  }

  @Test func theNextRunIsOfferedOnlyWhatCameSince() async throws {
    try await Self.withFeed(Self.agent(picking: .reply("挑好了。"))) { host, world, runner in
      runner.set(entries: Self.first)
      await RepairScenarioTests.fetch(1, on: host, world)
      world.tick()
      #expect(try await Background.ran(1, starting: Self.pick, on: host, world))

      runner.set(entries: Self.first + [Self.entry("a3", "港股午后拉升")])
      await RepairScenarioTests.fetch(1, on: host, world)
      world.tick()
      #expect(try await Background.ran(2, starting: Self.pick, on: host, world))

      let second = try #require(Self.pickPrompts(world).last)
      #expect(second.contains("[a3] 港股午后拉升"))
      #expect(!second.contains("[a1]"))
    }
  }

  @Test func pickedIdsAreFilledWithTheirOwnLinksAndTimes() async throws {
    try await Self.withFeed { host, world, runner in
      runner.set(entries: Self.first)
      await RepairScenarioTests.fetch(1, on: host, world)
      world.tick()
      let session = LocalSession.run(try await Background.runSession(world))

      let reply = await Background.call(
        PickPanelEntries("flash", ids: ["a1"], say: "**纳指期货**走高。"), from: session, on: host)

      #expect(reply == .value(try JSONEncoder().encode(Done())))
      let saved = try #require(host.store.home(.chat).panel(named: "flash")?.panel)
      #expect(saved.feed == Self.panel.feed)
      #expect(
        saved.body
          == .rows([
            .sentence("**纳指期货**走高。"),
            .list([
              PanelListItem(
                title: "纳指期货走高", subtitle: "+1.2%", at: "07:50", link: URL(string: "https://news.example/a1"))
            ]),
          ]))
    }
  }

  @Test func onlyTheEntriesThisRunWasShownMayBePicked() async throws {
    try await Self.withFeed { host, world, runner in
      runner.set(entries: Self.first)
      await RepairScenarioTests.fetch(1, on: host, world)
      world.tick()
      let session = LocalSession.run(try await Background.runSession(world))
      _ = try #require(await Self.firstPick(world))

      let skipped = await Background.call(PickPanelEntries("flash", ids: ["a2"], say: "x"), from: session, on: host)
      let unknown = await Background.call(PickPanelEntries("flash", ids: ["zz"], say: "x"), from: session, on: host)
      let other = await Background.call(
        PickPanelEntries("flash", ids: ["a1"], say: "x"), from: .run(world.nextID()), on: host)

      #expect(RepairScenarioTests.refusal(skipped) == "a2 were not among the entries shown this time; pick only those.")
      #expect(RepairScenarioTests.refusal(unknown) == "zz were not among the entries shown this time; pick only those.")
      #expect(RepairScenarioTests.refusal(other) != nil)
      #expect(host.store.home(.chat).panel(named: "flash")?.panel == Self.panel)
    }
  }

  @Test func aRunThatPicksMayNotSaveOrEditItsPanel() async throws {
    try await Self.withFeed { host, world, runner in
      runner.set(entries: Self.first)
      await RepairScenarioTests.fetch(1, on: host, world)
      world.tick()
      let session = LocalSession.run(try await Background.runSession(world))
      _ = try #require(await Self.firstPick(world))
      let rewritten = Self.panel.with(
        body: .rows([.sentence("x"), .list([PanelListItem(title: "假的", link: URL(string: "https://evil.example"))])]))

      let saved = await Background.call(SavePanel(rewritten), from: session, on: host)

      #expect(RepairScenarioTests.refusal(saved)?.contains("keep entries with loci panel pick") == true)
      #expect(host.store.home(.chat).panel(named: "flash")?.panel == Self.panel)
    }
  }

  @Test func entriesThatComeWhileARunGoesOnWaitForTheNext() async throws {
    let (gate, letGo) = AsyncStream.makeStream(of: Void.self)
    let agent = Self.agent(picking: .replyWhenLetGo("挑好了。", after: { for await _ in gate { return } }))
    try await Self.withFeed(agent) { host, world, runner in
      runner.set(entries: Self.first)
      await RepairScenarioTests.fetch(1, on: host, world)
      world.advance(minutes: 1)
      world.tick()
      _ = try #require(await Self.firstPick(world))

      runner.set(entries: Self.first + [Self.entry("a3", "港股午后拉升")])
      await RepairScenarioTests.fetch(1, on: host, world)
      runner.set(entries: Self.first + [Self.entry("a3", "港股午后拉升")])
      await RepairScenarioTests.fetch(1, on: host, world)
      letGo.yield()
      #expect(try await Background.ran(1, starting: Self.pick, on: host, world))
      world.tick()
      letGo.yield()

      #expect(try await Background.ran(2, starting: Self.pick, on: host, world))
      let second = try #require(Self.pickPrompts(world).last)
      #expect(second.contains("[a3] 港股午后拉升") && !second.contains("[a1]"))
    }
  }

  @Test func moreEntriesThanOneRunIsShownAreShownOverSeveralRuns() async throws {
    try await Self.withFeed(Self.agent(picking: .reply("挑好了。"))) { host, world, runner in
      let many = (1...35).map { Self.entry("n\($0)", "快讯 \($0)") }
      runner.set(entries: many)
      await RepairScenarioTests.fetch(1, on: host, world)
      world.advance(minutes: 1)
      world.tick()
      #expect(try await Background.ran(1, starting: Self.pick, on: host, world))
      world.tick()
      #expect(try await Background.ran(2, starting: Self.pick, on: host, world))

      let prompts = Self.pickPrompts(world)
      try #require(prompts.count == 2)
      let (first, second) = (prompts[0], prompts[1])
      #expect(first.contains("[n1] ") && first.contains("[n30] ") && !first.contains("[n31] "))
      #expect(second.contains("[n31] ") && second.contains("[n35] ") && !second.contains("[n30] "))
      world.tick()
      try await Background.quiet()
      #expect(Self.pickPrompts(world).count == 2)
    }
  }

  @Test func aBatchWhoseRunFailsIsNotRunAgainUntilNewEntriesCome() async throws {
    try await Self.withFeed(Self.agent(picking: .fail("no model answers"))) { host, world, runner in
      runner.set(entries: Self.first)
      await RepairScenarioTests.fetch(1, on: host, world)
      try await Self.failsOut(host, world, after: 0)
      #expect(try host.database.openEvents().isEmpty)

      await RepairScenarioTests.fetch(2, on: host, world)
      world.tick()
      try await Background.quiet()
      #expect(Self.pickPrompts(world).count == Run.tries)
      #expect(try host.database.openEvents().isEmpty)

      runner.set(entries: Self.first + [Self.entry("a3", "港股午后拉升")])
      await RepairScenarioTests.fetch(1, on: host, world)
      #expect(try host.database.openEvents().map(\.source) == [.panel(PanelRef("flash"), asked: false)])
    }
  }

  @Test func aFeedWhoseRunsKeepFailingWaitsForTheRefreshAskedFor() async throws {
    try await Self.withFeed(Self.agent(picking: .fail("no model answers"))) { host, world, runner in
      var entries = Self.first
      for round in 0..<PanelState.PanelStuck.mostRuns {
        entries.append(Self.entry("c\(round)", "快讯 \(round)"))
        runner.set(entries: entries)
        await RepairScenarioTests.fetch(1, on: host, world)
        try await Self.failsOut(host, world, after: round * Run.tries)
      }
      let failed = Self.pickPrompts(world).count
      #expect(failed == PanelState.PanelStuck.mostRuns * Run.tries)

      runner.set(entries: entries + [Self.entry("d1", "又一条")])
      await RepairScenarioTests.fetch(1, on: host, world)
      world.tick()
      try await Background.quiet()
      #expect(Self.pickPrompts(world).count == failed)
      #expect(try host.database.openEvents().isEmpty)

      _ = try await host.run(RefreshPanel(PanelRef("flash")))
      #expect(try await Background.ran(failed + 1, starting: Self.pick, on: host, world))
      #expect(Self.pickPrompts(world).last?.contains("[d1] 又一条") == true)
    }
  }

  /// Ticks the run that is due through each of its tries, every one failing; `after` picks were asked before.
  static func failsOut(_ host: LocalHost, _ world: TestWorld, after done: Int) async throws {
    for (index, wait) in ([0] + Worker.retryMinutes.prefix(Run.tries - 1)).enumerated() {
      world.advance(minutes: wait)
      world.tick()
      #expect(try await Background.ran(done + index + 1, starting: Self.pick, on: host, world))
    }
  }

  static func firstPick(_ world: TestWorld) async -> String? {
    for _ in 0..<500 {
      if let prompt = pickPrompts(world).first { return prompt }
      try? await Task.sleep(for: .milliseconds(10))
    }
    return nil
  }
}
