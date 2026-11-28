import Foundation
import LociModel
import LociStore
import Testing

@testable import LociHost

/// WT-S1–S3: each home has its own `WATCH.md`, read again for every batch; each fetch's new entries and numbers
/// are sorted by the tool model, which never takes the worker.
@Suite(.timeLimit(.minutes(1)))
struct WatchScenarioTests {
  static let entries = [
    SourceEntry(id: "policy", title: "国常会：加力发挥国家队稳市作用"),
    SourceEntry(id: "board", title: "龙虎榜：机构净买入 3 只个股"),
  ]

  @Test func theChatAndEachProjectHaveTheirOwnWatchFileAndTheCompanionIsToldHowToWriteIt() async throws {
    try await withHost { host, place, _ in
      let project = try await ProjectScenarioTests.start(host)
      #expect(FileManager.default.fileExists(atPath: place.root.appending(path: "agent/WATCH.md").path()))
      #expect(
        FileManager.default.fileExists(atPath: place.root.appending(path: "agent/projects/\(project)/WATCH.md").path()))
      #expect(try Prompts.bundled().rules.contains("WATCH.md"))
      let guide = try #require(ToolGuide.topics.first { $0.name == "watch" }?.text)
      #expect(guide.contains("Noise"))
      #expect(guide.contains("crosses"))
    }
  }

  @Test func aWatchFileEditedByHandIsWhatTheNextBatchIsReadWithAndOnlyInItsOwnHome() async throws {
    let model = TriageModel.discarding()
    let sources = FakeSources()
    try await withWatchHost(model: model, sources: sources) { host, place, world in
      let project = try await ProjectScenarioTests.start(host)
      _ = await Background.call(
        SaveDataSource(Watching.news), from: .conversation(.project(project)), on: host)
      try place.edit(place.root.appending(path: "agent/projects/\(project)/WATCH.md")) { _ in "稳市政策要告诉我。\n" }
      try place.edit(place.root.appending(path: "agent/WATCH.md")) { _ in "主对话只看论文。\n" }

      sources.set(entries: Self.entries)
      await Watching.fetchNext(on: host, world)
      try place.edit(place.root.appending(path: "agent/projects/\(project)/WATCH.md")) { _ in "龙虎榜也算。\n" }
      sources.set(entries: [SourceEntry(id: "board-2", title: "龙虎榜：游资")])
      await Watching.fetchNext(on: host, world)

      #expect(await model.inputs.map(\.watch) == ["稳市政策要告诉我。\n", "龙虎榜也算。\n"])
    }
  }

  @Test func newEntriesAreSortedOnceWithoutWakingTheCompanion() async throws {
    let model = TriageModel.discarding()
    let sources = FakeSources()
    try await withWatchHost(model: model, sources: sources) { host, _, world in
      _ = try await host.run(SaveDataSource(Watching.news))
      sources.set(entries: Self.entries)
      await Watching.fetchNext(on: host, world)
      await Watching.fetchNext(on: host, world)

      #expect(await model.inputs.map { $0.entries.map(\.id) } == [["policy", "board"]])
      #expect(try host.database.openEvents().isEmpty)
      #expect(world.agent.prompts.isEmpty)
      #expect(try host.database.waitingWatchBatches().isEmpty)
    }
  }

  @Test func triageGoesOnWhileARunTakesTheWorker() async throws {
    let model = TriageModel.discarding()
    let sources = FakeSources()
    let agent = Background.agent { _ in .hang }
    try await withHost(agent: agent, sources: sources, models: model) { host, _, world in
      _ = try await configureModels(host)
      _ = try await Background.add("busy", Background.draft(.hour), on: host)
      world.advance(minutes: 60)
      world.tick()
      _ = try await Background.runSession(world)
      _ = try await host.run(SaveDataSource(Watching.news))
      sources.set(entries: Self.entries)
      await Watching.fetchNext(on: host, world)

      #expect(await model.inputs.count == 1)
      #expect(try host.database.waitingWatchBatches().isEmpty)
    }
  }

  @Test func withoutAToolModelBatchesWaitAndAreReadOnceOneIsSet() async throws {
    let model = TriageModel.discarding()
    let sources = FakeSources()
    try await withHost(sources: sources, models: model) { host, _, world in
      _ = try await host.run(SaveDataSource(Watching.news))
      sources.set(entries: Self.entries)
      await Watching.fetchNext(on: host, world)
      #expect(try host.database.waitingWatchBatches().count == 1)

      _ = try await configureModels(host)
      await host.watchTriage.settled()

      #expect(await model.inputs.count == 1)
      #expect(try host.database.waitingWatchBatches().isEmpty)
    }
  }

  @Test func aPanelThatFollowsTheSourceShowsWhatTriageChoseWithTheEntrysOwnLink() async throws {
    let model = TriageModel { input in
      TriageDecision.reply(
        input.entries.map { $0.id == "policy" ? .panel("policy", "flash", "午间政策") : .discard($0.id) })
    }
    let sources = FakeSources()
    try await withWatchHost(model: model, sources: sources) { host, _, world in
      let panel = Panel(
        name: "flash", title: "快讯", follow: "政策", feed: PanelFeed(source: "news"),
        body: .rows([.sentence("还没有新快讯。")]))
      _ = try await host.run(SaveDataSource(Watching.news))
      _ = try await host.run(SavePanel(panel))
      let link = try #require(URL(string: "https://www.cls.cn/detail/2546318"))
      sources.set(entries: [
        SourceEntry(id: "policy", title: "国常会：加力发挥国家队稳市作用", url: link, at: world.now), Self.entries[1],
      ])
      await Watching.fetchNext(on: host, world)

      let saved = host.store.home(.chat).panel(named: "flash")?.panel
      guard case .rows(let rows)? = saved?.body, case .list(let items) = rows.last else {
        Issue.record("the panel kept no list")
        return
      }
      #expect(rows.first == .sentence("午间政策"))
      #expect(items.map(\.title) == ["国常会：加力发挥国家队稳市作用"])
      #expect(items.first?.link == link)
      #expect(world.agent.prompts.isEmpty)
      #expect(await model.inputs.first?.panels == ["flash"])
    }
  }
}
