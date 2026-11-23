import Foundation
import LociModel
import LociStore
import Testing

@testable import LociHost

/// P-S17–P-S24: the person writes in panels one edit at a time, and whatever Loci saves keeps what is theirs.
@Suite(.timeLimit(.minutes(1)))
struct PanelEditScenarioTests {
  static func item(_ id: String, _ text: String, by: PanelItem.Author = .loci) -> PanelItem {
    PanelItem(id: id, text: text, by: by)
  }

  static let notes = item("notes", "整理面试笔记")
  static let week = Panel(
    name: "week", title: "本周待办", follow: "这周要做的事",
    body: .rows([
      .items(PanelItems(id: "today", name: "今天", adds: true, checks: true, items: [notes])),
      .items(PanelItems(id: "week", name: "本周", adds: true, checks: true, items: [])),
    ]))
  static let radar = Panel(
    name: "radar", title: "沙箱雷达", follow: "盯着沙箱", refresh: PanelRefresh(every: .day, at: "10:00"),
    body: .rows([
      .sentence("**firecracker** 合并了增量恢复。"),
      .list([
        PanelListItem(title: "HN 热议", link: URL(string: "https://news.ycombinator.com/item?id=1")),
        PanelListItem(title: "kata 4.4 发布说明"),
      ]),
    ]))

  private actor Replies {
    var all: [LocalReply] = []
    func add(_ reply: LocalReply) { all.append(reply) }
  }

  private func loci<C: Command>(_ command: C, from session: LocalSession?, on host: LocalHost) async throws
    -> LocalReply?
  {
    let replies = Replies()
    let request = LocalCall.Request.command(name: C.name, body: try JSONEncoder().encode(command))
    await ToolGateway.answer(LocalCall(session: session, request: request), on: host) { await replies.add($0) }
    return await replies.all.first
  }

  private func shown(_ host: LocalHost, _ name: String) async throws -> Panel {
    try #require(try await host.panels().first { $0.name == name }?.panel)
  }

  private func refreshSession(_ world: TestWorld) async throws -> LocalSession {
    for _ in 0..<200 {
      let told = world.agent.opened.compactMap { $0.environment[LocalCall.sessionVariable] }
      if let session = told.compactMap(LocalSession.init(tag:)).first(where: { $0.conversation == nil }) {
        return session
      }
      try await Task.sleep(for: .milliseconds(10))
    }
    throw HostError.notFound("refresh session")
  }

  static var done: LocalReply { .value((try? JSONEncoder().encode(Done())) ?? Data()) }

  @Test func thePersonSItemIsWrittenToThePanelFile() async throws {
    try await withHost { host, place, _ in
      _ = try await host.run(SavePanel(Self.week))

      _ = try await host.run(EditPanel("week", .put(.yours(id: "cat", text: "买猫粮"), section: "today", at: 0)))

      let file = try String(contentsOf: place.root.appending(path: "agent/panels/week.json"), encoding: .utf8)
      #expect(file.contains(#""by" : "you""#) && file.contains("买猫粮"))
      #expect(try await shown(host, "week").sections[0].items.map(\.text) == ["买猫粮", "整理面试笔记"])
      await #expect(throws: HostError.self) { try await host.run(EditPanel("week", .remove("gone"))) }
    }
  }

  @Test func aRefreshKeepsThePersonSItemsAndTheirTakeOnLociS() async throws {
    try await withHost(agent: PanelRefreshScenarioTests.agent(refreshing: .hang)) { host, _, world in
      _ = try await host.run(SavePanel(Self.week))
      _ = try await host.run(RefreshPanel("week"))
      let session = try await refreshSession(world)
      var pinned = Self.notes
      pinned.pinned = true
      pinned.note = "周四前"

      _ = try await host.run(EditPanel("week", .put(.yours(id: "cat", text: "买猫粮"), section: "week", at: nil)))
      _ = try await host.run(EditPanel("week", .put(pinned, section: "today", at: nil)))
      let saved = try await loci(SavePanel(Self.week), from: session, on: host)

      #expect(saved == Self.done)
      let panel = try await shown(host, "week")
      #expect(panel.sections[0].items == [pinned])
      #expect(panel.sections[1].items == [.yours(id: "cat", text: "买猫粮")])
    }
  }

  @Test func aRefreshDoesNotBringBackLociSItemThePersonRemoved() async throws {
    try await withHost(agent: PanelRefreshScenarioTests.agent(refreshing: .hang)) { host, _, world in
      _ = try await host.run(SavePanel(Self.week))
      _ = try await host.run(RefreshPanel("week"))
      let session = try await refreshSession(world)

      _ = try await host.run(EditPanel("week", .remove("notes")))
      let saved = try await loci(SavePanel(Self.week), from: session, on: host)

      #expect(saved == Self.done)
      #expect(try await shown(host, "week").sections[0].items.isEmpty)
    }
  }

  @Test func lociAddsAnItemOfItsOwnButCannotRemoveOrRewordThePersonS() async throws {
    try await withHost { host, _, _ in
      _ = try await host.run(SavePanel(Self.week))
      _ = try await host.run(EditPanel("week", .put(.yours(id: "cat", text: "买猫粮"), section: "today", at: nil)))
      let main = LocalSession.conversation(.main)

      let added = try await loci(
        EditPanel("week", .put(.yours(id: "kata", text: "回 Kata 的 review"), section: "week", at: nil)), from: main,
        on: host)
      let removed = try await loci(EditPanel("week", .remove("cat")), from: main, on: host)
      let reworded = try await loci(
        EditPanel("week", .put(.yours(id: "cat", text: "买狗粮"), section: "today", at: nil)), from: main, on: host)

      #expect(added == Self.done)
      #expect(removed == .failed(.invalidRequest(#""cat" is the person's item; only they can remove it"#)))
      #expect(reworded == .failed(.invalidRequest(#""cat" is the person's item; keep their words"#)))
      let panel = try await shown(host, "week")
      #expect(panel.sections[1].items == [Self.item("kata", "回 Kata 的 review")])
      #expect(panel.sections[0].items.last == .yours(id: "cat", text: "买猫粮"))
    }
  }

  @Test func aRefreshEditsOnlyItsOwnPanelAndOnlyWhileItIsWanted() async throws {
    try await withHost(agent: PanelRefreshScenarioTests.agent(refreshing: .hang)) { host, _, world in
      _ = try await host.run(SavePanel(Self.week))
      _ = try await host.run(SavePanel(PanelScenarioTests.radar))
      _ = try await host.run(RefreshPanel("week"))
      let session = try await refreshSession(world)
      let edit = PanelEdit.put(Self.item("a", "一"), section: "week", at: nil)

      let other = try await loci(EditPanel("radar", edit), from: session, on: host)
      let own = try await loci(EditPanel("week", edit), from: session, on: host)
      _ = try await host.run(RemovePanel("week"))
      let late = try await loci(EditPanel("week", edit), from: session, on: host)

      #expect(other == .failed(.invalidRequest("This refresh is of week; it can save only that panel.")))
      #expect(own == Self.done)
      #expect(late == .failed(.invalidRequest(PanelKeeper.stopped)))
    }
  }

  @Test func editsAndLociSSavesTakeTurns() async throws {
    try await withHost { host, _, _ in
      _ = try await host.run(SavePanel(Self.week))

      try await withThrowingTaskGroup(of: Void.self) { group in
        for index in 0..<10 {
          group.addTask {
            _ = try await host.run(
              EditPanel("week", .put(.yours(id: "i\(index)", text: "第 \(index) 条"), section: "week", at: nil)))
          }
        }
        group.addTask {
          _ = try await self.loci(SavePanel(Self.week), from: .conversation(.main), on: host)
        }
        try await group.waitForAll()
      }

      #expect(try await shown(host, "week").sections[1].items.count == 10)
    }
  }

  @Test func aLineThePersonNoLongerWantsIsKeptOutOfLociSReachAndToldToTheRefresh() async throws {
    try await withHost(agent: PanelRefreshScenarioTests.agent(refreshing: .hang)) { host, place, world in
      _ = try await host.run(SavePanel(Self.radar))
      guard case .rows(let rows) = Self.radar.body, case .list(let lines) = rows[1] else { return }
      let hn = PanelLineKey(lines[0])

      _ = try await host.run(MarkPanelLine("radar", hn, PanelLineMark(hidden: true)))
      _ = try await host.run(MarkPanelLine("radar", PanelLineKey(lines[1]), PanelLineMark(pinned: true, note: "看")))
      _ = try await host.run(RefreshPanel("radar"))
      _ = try await refreshSession(world)

      #expect(try await host.panelColumn().marks["radar"]?[hn] == PanelLineMark(hidden: true))
      let prompt = try #require(world.agent.prompts.last { $0.hasPrefix("Refresh the panel") })
      #expect(prompt.contains("- HN 热议 (https://news.ycombinator.com/item?id=1)"))
      #expect(!prompt.contains("- kata 4.4 发布说明"))
      _ = try await host.run(RemovePanel("radar"))
      #expect(place.store.panelState().marks["radar"] == nil)
    }
  }

  @Test func eachTurnShowsWhatThePersonWroteInPanelsOnceAndAgainWhenItChanges() async throws {
    try await withHost { host, _, world in
      _ = try await host.run(SavePanel(Self.week))
      _ = try await host.run(EditPanel("week", .put(.yours(id: "cat", text: "买猫粮"), section: "today", at: nil)))

      _ = try await host.run(SendMessage(to: .main, text: "one"))
      _ = try #require(await settled(host, prompts: 1))
      _ = try await host.run(SendMessage(to: .main, text: "two"))
      _ = try #require(await settled(host, prompts: 2))
      var done = PanelItem.yours(id: "cat", text: "买猫粮")
      done.done = true
      _ = try await host.run(EditPanel("week", .put(done, section: "today", at: nil)))
      _ = try await host.run(SendMessage(to: .main, text: "three"))
      _ = try #require(await settled(host, prompts: 3))

      let prompts = world.agent.prompts
      #expect(prompts[0].contains("Panels (what the person wrote and marked):\n- 本周待办 › 今天: 买猫粮"))
      #expect(!prompts[1].contains("Panels (what the person wrote"))
      #expect(prompts[2].contains("Panels (what the person wrote and marked):\n(empty)"))
    }
  }

  @Test func anotherMacWritesInPanelsToo() async throws {
    try await TwoMacs.with { macs in
      try await macs.pair()
      let remote = macs.laptop.service.open(macs.studio.machine.id)
      _ = try await macs.studio.local.run(SavePanel(Self.week))

      _ = try await remote.run(EditPanel("week", .put(.yours(id: "cat", text: "买猫粮"), section: "week", at: nil)))

      let column = await value(remote.subscribe(WatchPanelColumn())) { column in
        column.slots.contains { slot in
          if case .panel(let panel) = slot { panel.sections.last?.items.first?.text == "买猫粮" } else { false }
        }
      }
      #expect(column != nil)
    }
  }

  @Test func thePanelSummaryKeepsToItsLimit() {
    let items = (0..<40).map { PanelItem.yours(id: "i\($0)", text: "第 \($0) 条") }
    let panel = Panel(
      name: "week", title: "本周待办", follow: "x",
      body: .rows([.items(PanelItems(id: "week", name: "本周", items: items))]))

    let summary = PanelSummary.of([panel], marks: [:])

    #expect(summary.contains("- 本周待办 › 本周: 第 0 条"))
    #expect(!summary.contains("第 39 条"))
    #expect(summary.hasSuffix("…and \(40 - PanelSummary.limit) more."))
  }
}
