import Foundation
import LociModel
import LociStore
import Testing

@testable import LociHost

/// WK-S1, WK-S2, WK-S3, WK-S5, WK-S7: schedules the companion sets, run on their own in the background.
@Suite(.timeLimit(.minutes(1)))
struct ScheduleScenarioTests {
  static let found = "看了 releases 和 PR。CubeSandbox 发了 **v0.9.0**，修了快照恢复。"

  static func noting(_ prompt: String) -> FakeAgent.Behavior {
    .write(["notes/2025-11-17.md": "# 2025-11-17\n\n- 21:01 [run/x] CubeSandbox 发了 v0.9.0\n"], reply: found)
  }

  @Test func aScheduleAddedWithLociRunsAtItsTimeInASessionNoConversationShows() async throws {
    try await withHost(agent: Background.agent(run: Self.noting)) { host, place, world in
      let entry = try await Background.add(
        "sandbox-news", Background.draft(.day(at: try Background.clock("21:00"))), on: host)
      world.set(to: "20:59")
      world.tick()
      try await Background.quiet()
      #expect(Background.prompts(world, starting: Background.lookInto).isEmpty)

      world.set(to: "21:00")
      world.tick()

      let runs = try #require(await Background.runs(of: entry.ref, on: host, where: Background.finished))
      #expect(entry.next == world.now)
      let run = try #require(runs.first)
      #expect(run.outcome == .finished(summary: "CubeSandbox 发了 **v0.9.0**，修了快照恢复。", sources: []))
      #expect(try await Background.runSession(world) == run.id)
      let prompt = try #require(Background.prompts(world, starting: Background.lookInto).first)
      #expect(prompt.contains("看看 CubeSandbox 有什么新动静") && prompt.contains("[run/\(run.id)]"))
      #expect(!prompt.contains("loci-context") && prompt.contains("first run"))
      let record = try #require(try place.store.runRecord(at: run.record))
      #expect(record.contains("## Summary") && record.contains("schedule sandbox-news"))
      #expect(try await host.conversation(.main).messages.isEmpty)
      #expect(try await host.timers().schedules.first?.lastSummary == "CubeSandbox 发了 **v0.9.0**，修了快照恢复。")
      #expect(try await host.timers().schedules.first?.lastRun == run.startedAt)
    }
  }

  @Test func aRunIsToldWhatTheLastRunOfItsScheduleFoundAndThePanelAsItIs() async throws {
    let hidden = PanelListItem(title: "#12 旧 issue", link: URL(string: "https://github.com/x/y/issues/12"))
    let panel = Panel(
      name: "sandbox-radar", title: "沙箱雷达", follow: "盯着 CubeSandbox",
      body: .rows([.sentence("**v0.8.0** 发布。"), .list([hidden])]))
    try await withHost(agent: Background.agent(run: Self.noting)) { host, _, world in
      _ = try await host.run(SavePanel(panel))
      _ = try await host.run(
        MarkPanelLine(PanelRef("sandbox-radar"), PanelLineKey(hidden), PanelLineMark(hidden: true)))
      let entry = try await Background.add(
        "sandbox-news", Background.draft(.hour, to: .panel("sandbox-radar")), on: host)

      world.advance(minutes: 60)
      world.tick()
      _ = await Background.runs(of: entry.ref, on: host, where: Background.finished)
      world.advance(minutes: 60)
      world.tick()
      let runs = try #require(
        await Background.runs(of: entry.ref, on: host) { $0.count == 2 && Background.finished($0) })

      let prompts = Background.prompts(world, starting: Background.lookInto)
      #expect(prompts.count == 2)
      #expect(prompts[0].contains("panel save sandbox-radar") && prompts[0].contains(#""title" : "沙箱雷达""#))
      #expect(prompts[0].contains("#12 旧 issue") && prompts[0].contains("no longer wants to see"))
      #expect(prompts[1].contains("What the last run of this schedule found (`\(runs[1].record)`)"))
      #expect(prompts[1].contains("CubeSandbox 发了 **v0.9.0**"))
    }
  }

  @Test func aScheduleMissedForDaysRunsOnceWhenTheMacWakes() async throws {
    try await withHost(agent: Background.agent(run: Self.noting)) { host, _, world in
      let entry = try await Background.add(
        "sandbox-news", Background.draft(.day(at: try Background.clock("21:00"))), on: host)
      world.set(to: "08:00", daysLater: 3)

      world.tick()
      _ = await Background.runs(of: entry.ref, on: host, where: Background.finished)
      world.tick()
      try await Background.quiet()

      #expect(Background.prompts(world, starting: Background.lookInto).count == 1)
      #expect(try await host.runs(of: entry.ref, limit: 10).count == 1)
    }
  }

  @Test func aPausedScheduleDoesNotRunAndItsTimeCanBeChanged() async throws {
    try await withHost(agent: Background.agent(run: Self.noting)) { host, _, world in
      let entry = try await Background.add(
        "sandbox-news", Background.draft(.day(at: try Background.clock("21:00"))), on: host)

      _ = try await host.run(PauseSchedule(entry.ref, paused: true))
      world.set(to: "21:00")
      world.tick()
      try await Background.quiet()
      #expect(Background.prompts(world, starting: Background.lookInto).isEmpty)
      #expect(try await host.timers().schedules.map(\.paused) == [true])
      #expect(try await host.timers().next == nil)

      _ = try await host.run(PauseSchedule(entry.ref, paused: false))
      let changed = try await host.run(ChangeSchedule(entry.ref, every: .day(at: try Background.clock("22:00"))))
      world.set(to: "21:30")
      #expect(try await host.timers().schedules.first?.next == changed.next)
      #expect(changed.next.map { TimeOfDay(of: $0, in: TestWorld.timeZone) } == TimeOfDay("22:00"))

      _ = try await host.run(RemoveSchedule(entry.ref))
      #expect(try await host.timers().schedules.isEmpty)
    }
  }

  @Test func theCompanionMovesAScheduleItSetToAnotherTimeAndKeepsWhatItDidNotChange() async throws {
    try await withHost(agent: Background.agent(run: Self.noting)) { host, _, world in
      _ = try await host.run(SavePanel(PanelScenarioTests.panel("sandbox-radar")))
      let entry = try await Background.add(
        "sandbox-news", Background.draft(.day(at: try Background.clock("21:00"))), on: host)
      let change = ScheduleChange(every: .day(at: try Background.clock("15:49")), destination: .panel("sandbox-radar"))

      let reply = await Background.call(ChangeSchedule(entry.ref, change), from: .conversation(.main), on: host)

      guard case .value(let data)? = reply else { throw HostError.invalidRequest("\(String(describing: reply))") }
      let changed = try JSONDecoder().decode(ScheduleEntry.self, from: data)
      #expect(changed.every == .day(at: try Background.clock("15:49")))
      #expect(changed.destination == .panel("sandbox-radar") && changed.title == entry.title)
      #expect(changed.next.map { TimeOfDay(of: $0, in: TestWorld.timeZone) } == TimeOfDay("15:49"))
      world.set(to: "15:49")
      world.tick()
      #expect(try await Background.ran(1, starting: Background.lookInto, on: host, world))
      let prompt = try #require(Background.prompts(world, starting: Background.lookInto).first)
      #expect(prompt.contains("看看 CubeSandbox 有什么新动静") && prompt.contains("panel save sandbox-radar"))
    }
  }

  @Test func aPanelsRefreshChangesInItsFileButStaysWithThatPanel() async throws {
    try await withHost(agent: Background.agent(run: Self.noting)) { host, place, _ in
      _ = try await host.run(SavePanel(PanelScenarioTests.radar))
      let hourly = ScheduleChange(title: "沙箱快讯", every: .hour)

      let changed = try await host.run(ChangeSchedule(.panel(PanelRef("radar")), hourly))

      #expect(changed.every == .hour && changed.title == "沙箱快讯")
      let panel = try #require(place.store.home(.chat).panel(named: "radar")?.panel)
      #expect(panel.refresh == PanelRefresh(every: .hour) && panel.title == "沙箱快讯")
      await #expect(throws: HostError.self) {
        _ = try await host.run(ChangeSchedule(.panel(PanelRef("radar")), ScheduleChange(destination: .notes)))
      }
    }
  }

  @Test func aPanelsRefreshIsAmongTheSchedulesAndRemovingItKeepsThePanel() async throws {
    try await withHost(agent: Background.agent(run: Self.noting)) { host, _, _ in
      _ = try await host.run(SavePanel(PanelScenarioTests.radar))

      let listed = try await host.timers().schedules
      #expect(listed.map(\.ref) == [.panel(PanelRef("radar"))])
      #expect(listed.first?.destination == .panel("radar"))
      _ = try await host.run(PauseSchedule(.panel(PanelRef("radar")), paused: true))
      #expect(try await host.timers().schedules.first?.paused == true)

      _ = try await host.run(RemoveSchedule(.panel(PanelRef("radar"))))

      #expect(try await host.timers().schedules.isEmpty)
      #expect(try await host.panelColumn(of: .chat).slots.map(\.place) == [.panel("radar")])
    }
  }

  @Test func aScheduleNeedsAFreeNameAndAPanelThatIsThere() async throws {
    try await withHost(agent: Background.agent(run: Self.noting)) { host, _, _ in
      _ = try await Background.add("sandbox-news", Background.draft(.hour), on: host)

      let taken = await Background.call(
        AddSchedule("sandbox-news", Background.draft(.hour)), from: .conversation(.main), on: host)
      let nowhere = await Background.call(
        AddSchedule("other", Background.draft(.hour, to: .panel("nothing"))), from: .conversation(.main), on: host)

      #expect(taken.map { if case .failed(.invalidRequest) = $0 { true } else { false } } == true)
      #expect(nowhere.map { if case .failed(.invalidRequest) = $0 { true } else { false } } == true)
    }
  }
}
