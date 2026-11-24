import Foundation
import LociModel
import LociStore
import Testing

@testable import LociHost

/// WK-S7, WK-S8: one worker in the background, one run at a time, never while the person is talking.
@Suite(.timeLimit(.minutes(1)))
struct WorkerScenarioTests {
  @Test func noRunStartsWhileThePersonIsTalking() async throws {
    let agent = Background.agent(main: .hang) { _ in .reply("看了。没有新动静。") }
    try await withHost(agent: agent) { host, _, world in
      _ = try await Background.add("sandbox-news", Background.draft(.hour), on: host)
      _ = try await host.run(SendMessage(to: .main, text: "Hi"))
      world.advance(minutes: 60)

      world.tick()
      try await Background.quiet()
      #expect(Background.prompts(world, starting: Background.lookInto).isEmpty)

      _ = try await host.run(StopTurn(in: .main))
      world.tick()
      #expect(try await Background.ran(1, starting: Background.lookInto, on: host, world))
    }
  }

  @Test func schedulesDueInTheSameMinuteShareOneRun() async throws {
    try await withHost(agent: Background.agent { _ in .reply("看了。都没变。") }) { host, _, world in
      let nine = Every.day(at: try Background.clock("21:00"))
      let first = try await Background.add("sandbox-news", Background.draft(nine), on: host)
      let second = try await Background.add("k8s-news", Background.draft(nine, follow: "看看 k8s 调度器"), on: host)
      world.set(to: "21:00")

      world.tick()

      #expect(try await Background.ran(1, starting: Background.together, on: host, world))
      let prompt = try #require(Background.prompts(world, starting: Background.together).first)
      #expect(prompt.contains("看看 CubeSandbox 有什么新动静") && prompt.contains("看看 k8s 调度器"))
      let one = try await host.runs(of: first.ref, limit: 5)
      let two = try await host.runs(of: second.ref, limit: 5)
      #expect(one.count == 1 && one.map(\.id) == two.map(\.id))
      #expect(world.agent.prompts.count == 1)
    }
  }

  @Test func aRunThatFailsIsTriedThreeTimesWaitingLongerEachTimeThenGivenUp() async throws {
    try await withHost(agent: Background.agent { _ in .fail("network down") }) { host, place, world in
      let entry = try await Background.add("sandbox-news", Background.draft(.hour), on: host)
      world.advance(minutes: 60)
      world.tick()
      #expect(try await Background.ran(1, starting: Background.lookInto, on: host, world))

      world.tick()
      try await Background.quiet()
      #expect(Background.prompts(world, starting: Background.lookInto).count == 1)
      world.advance(minutes: 1)
      world.tick()
      #expect(try await Background.ran(2, starting: Background.lookInto, on: host, world))
      world.advance(minutes: 4)
      world.tick()
      try await Background.quiet()
      #expect(Background.prompts(world, starting: Background.lookInto).count == 2)
      world.advance(minutes: 1)
      world.tick()
      #expect(try await Background.ran(3, starting: Background.lookInto, on: host, world))

      let run = try #require(try await host.runs(of: entry.ref, limit: 5).first)
      #expect(try await host.runs(of: entry.ref, limit: 5).count == 1)
      #expect(run.outcome == .failed("network down", tries: 3))
      let record = try #require(try place.store.runRecord(at: run.record))
      #expect(record.contains("## Try 1 failed") && record.contains("## Try 3 failed"))
      #expect(record.contains("Given up after 3 tries."))
    }
  }

  @Test func aRunCutShortByQuittingIsDoneAgainAsTheSameRunWhenTheAppOpens() async throws {
    let place = Place()
    defer { place.remove() }
    let first = TestWorld(agent: Background.agent { _ in .hang })
    let quitting = try await LocalHost.start(root: place.root, database: place.database, environment: first.environment)
    let entry = try await Background.add("sandbox-news", Background.draft(.hour), on: quitting)
    first.advance(minutes: 60)
    first.tick()
    let run = try await Background.runSession(first)
    await quitting.close()

    let second = TestWorld(agent: Background.agent { _ in .reply("看了。没有新动静。") }, idOffset: 1000)
    let host = try await LocalHost.start(root: place.root, database: place.database, environment: second.environment)
    second.tick()
    let ran = try await Background.ran(1, starting: Background.lookInto, on: host, second)
    let runs = try await host.runs(of: entry.ref, limit: 5)
    await host.close()

    #expect(ran)
    let prompt = try #require(Background.prompts(second, starting: Background.lookInto).first)
    #expect(prompt.contains("An earlier try of this run stopped partway") && prompt.contains("[run/\(run)]"))
    #expect(runs.map(\.id) == [run])
    #expect(runs.first?.outcome == .finished(summary: "没有新动静。", sources: []))
  }

  @Test func aRunHoldsOffAppNapWhileItRunsAndLetsGoAfter() async throws {
    try await withHost(agent: Background.agent { _ in .reply("看了。没有新动静。") }) { host, _, world in
      _ = try await Background.add("sandbox-news", Background.draft(.hour), on: host)
      #expect(world.activity.isEmpty)
      world.advance(minutes: 60)

      world.tick()

      #expect(try await Background.ran(1, starting: Background.lookInto, on: host, world))
      #expect(world.activity == ["begin", "end"])
    }
  }

  @Test func theStatusSaysWhichScheduleIsBeingLookedInto() async throws {
    try await withHost(agent: Background.agent { _ in .hang }) { host, _, world in
      _ = try await Background.add("sandbox-news", Background.draft(.hour), on: host)
      world.advance(minutes: 60)

      world.tick()

      #expect(await value(host.subscribe(LociWorking())) { $0.work == .looking(title: "CubeSandbox 动静") } != nil)
    }
  }
}

/// WK-S10: in a run in the background, `loci` only reads, sets follow-ups and saves the run's own panel.
@Suite(.timeLimit(.minutes(1)))
struct RunToolScenarioTests {
  static func refused(_ reply: LocalReply?) -> String? {
    if case .failed(.invalidRequest(let reason))? = reply { reason } else { nil }
  }

  static func worked(_ reply: LocalReply?) -> Bool {
    if case .value? = reply { true } else { false }
  }

  @Test func aRunReadsSetsFollowUpsAndSavesOnlyItsPanel() async throws {
    try await withHost(agent: Background.agent { _ in .hang }) { host, _, world in
      _ = try await host.run(SavePanel(PanelScenarioTests.panel("sandbox-radar")))
      _ = try await host.run(SavePanel(PanelScenarioTests.panel("other")))
      _ = try await Background.add("sandbox-news", Background.draft(.hour, to: .panel("sandbox-radar")), on: host)
      world.advance(minutes: 60)
      world.tick()
      let session = LocalSession.run(try await Background.runSession(world))
      let link = try #require(URL(string: "https://example.com/a"))
      func call<C: Command>(_ command: C) async -> LocalReply? {
        await Background.call(command, from: session, on: host)
      }

      #expect(Self.worked(await call(Search(text: "borg"))))
      #expect(Self.worked(await call(ListTimers())))
      #expect(Self.worked(await call(AddFollowUp(.after(minutes: 60), "再看看"))))
      #expect(Self.worked(await call(SavePanel(PanelScenarioTests.panel("sandbox-radar", title: "雷达")))))
      #expect(
        Self.refused(await call(AddLink(url: link)))
          == RunPolicy.timers.refusal(AddLink.name))
      #expect(
        Self.refused(await call(AddSchedule("more", Background.draft(.hour))))
          == RunPolicy.timers.refusal(AddSchedule.name))
      #expect(
        Self.refused(await call(SavePanel(PanelScenarioTests.panel("other", title: "x"))))
          == "This refresh is of sandbox-radar; it can save only that panel.")
      #expect(
        Self.refused(await Background.call(.feeling(.sleep), from: session, on: host))
          == RunPolicy.timers.refusal("mood"))
      #expect(Self.refused(await Background.call(.upload(path: "/tmp/a.mp4"), from: session, on: host)) != nil)
      #expect(try await host.run(ListItems()).isEmpty)
      #expect(try await host.timers().followUps.map(\.conversation) == [nil])
    }
  }

  @Test func theDailyReviewMaySetItsMoodButNotSaveOrKeepPanels() async throws {
    let agent = FakeAgent(provider: .codex) { prompt in prompt.hasPrefix("It is the end of") ? .hang : .reply("Hi.") }
    try await withHost(agent: agent) { host, _, world in
      _ = try await host.run(SavePanel(PanelScenarioTests.panel("other")))
      world.set(to: "22:00")
      _ = try await host.run(SendMessage(to: .main, text: "Hi"))
      _ = await settled(host)
      world.set(to: "23:30")
      world.tick()
      let session = LocalSession.run(try await Background.runSession(world))
      let link = try #require(URL(string: "https://example.com/a"))

      let mood = await Background.call(
        .feeling(.base(word: "平静", valence: try #require(Score(6)), energy: try #require(Score(4)), why: "一天过完了")),
        from: session, on: host)
      let saved = await Background.call(AddLink(url: link), from: session, on: host)
      let panel = await Background.call(SavePanel(PanelScenarioTests.panel("other")), from: session, on: host)

      #expect(Self.worked(mood))
      #expect(Self.refused(saved) == RunPolicy.review.refusal(AddLink.name))
      #expect(Self.refused(panel) == "This run cannot save panels.")
    }
  }
}
