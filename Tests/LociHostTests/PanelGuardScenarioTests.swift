import Foundation
import LociModel
import LociStore
import Testing

@testable import LociHost

/// P-S7, P-S8, P-S10: what stays shown across a restart, and what a refresh may still do.
@Suite(.timeLimit(.minutes(1)))
struct PanelGuardScenarioTests {
  private actor Replies {
    var all: [LocalReply] = []
    func add(_ reply: LocalReply) { all.append(reply) }
  }

  private func answer(_ request: LocalCall.Request, from session: LocalSession?, on host: LocalHost) async
    -> LocalReply?
  {
    let replies = Replies()
    await ToolGateway.answer(LocalCall(session: session, request: request), on: host) { await replies.add($0) }
    return await replies.all.first
  }

  private func command<C: Command>(_ command: C) throws -> LocalCall.Request {
    .command(name: C.name, body: try JSONEncoder().encode(command))
  }

  /// The session the refresh under way was opened with, once it is.
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

  private func refreshEnded(_ host: LocalHost) async -> Bool {
    await value(host.subscribe(WatchPanelColumn())) { $0.refreshing.isEmpty } != nil
  }

  @Test func aFileBrokenByHandStillShowsItsLastGoodPanelAfterARestart() async throws {
    let place = Place()
    defer { place.remove() }
    let world = TestWorld()
    let first = try await LocalHost.start(root: place.root, database: place.database, environment: world.environment)
    _ = try await first.run(SavePanel(PanelScenarioTests.radar))
    await first.close()
    try Data("{ broken".utf8).write(to: place.root.appending(path: "agent/panels/radar.json"))

    let second = try await LocalHost.start(root: place.root, database: place.database, environment: world.environment)

    #expect(try await second.panelColumn(of: .chat).slots == [.panel(PanelScenarioTests.radar)])
    _ = try await second.run(RemovePanel(PanelRef("radar")))
    try Data("{ broken".utf8).write(to: place.root.appending(path: "agent/panels/radar.json"))
    #expect(try await second.panelColumn(of: .chat).slots.isEmpty)
    await second.close()
  }

  @Test func aRefreshWhosePanelWasRemovedCannotSaveItBack() async throws {
    let agent = PanelRefreshScenarioTests.agent(refreshing: .hang)
    try await withHost(agent: agent) { host, place, world in
      _ = try await host.run(SavePanel(PanelScenarioTests.radar))
      _ = try await host.run(RefreshPanel(PanelRef("radar")))
      let session = try await refreshSession(world)

      _ = try await host.run(RemovePanel(PanelRef("radar")))
      let saved = await answer(try command(SavePanel(PanelScenarioTests.radar)), from: session, on: host)

      #expect(saved == .failed(.invalidRequest(PanelKeeper.stopped)))
      #expect(!FileManager.default.fileExists(atPath: place.root.appending(path: "agent/panels/radar.json").path()))
      #expect(await refreshEnded(host))
      #expect(try await host.panelColumn(of: .chat).slots.isEmpty)
    }
  }

  @Test func aRefreshThatIsOverCannotSave() async throws {
    try await withHost(agent: PanelRefreshScenarioTests.agent()) { host, _, world in
      _ = try await host.run(SavePanel(PanelScenarioTests.radar))
      _ = try await host.run(RefreshPanel(PanelRef("radar")))
      let session = try await refreshSession(world)
      #expect(await refreshEnded(host))

      let saved = await answer(try command(SavePanel(PanelScenarioTests.radar)), from: session, on: host)

      #expect(saved == .failed(.invalidRequest(ToolGateway.over)))
      #expect(try await host.panelColumn(of: .chat).slots.map(\.place) == [.panel("radar")])
    }
  }

  @Test func aRefreshReadsAndSavesOnlyItsOwnPanel() async throws {
    try await withHost(agent: PanelRefreshScenarioTests.agent(refreshing: .hang)) { host, _, world in
      _ = try await host.run(SavePanel(PanelScenarioTests.radar))
      _ = try await host.run(SavePanel(PanelScenarioTests.panel("other")))
      _ = try await host.run(RefreshPanel(PanelRef("radar")))
      let session = try await refreshSession(world)
      let link = try #require(URL(string: "https://example.com/a"))
      let renamed = Panel(
        name: "radar", title: "沙箱快讯", follow: "x", body: .rows([.sentence("**v0.9.0** 发布。")]))

      let listed = await answer(try command(ListPanels()), from: session, on: host)
      let searched = await answer(try command(Search(text: "borg")), from: session, on: host)
      let added = await answer(try command(AddLink(url: link)), from: session, on: host)
      let uploaded = await answer(.upload(path: "/tmp/a.mp4"), from: session, on: host)
      let other = await answer(
        try command(SavePanel(PanelScenarioTests.panel("other", title: "x"))), from: session, on: host)
      let own = await answer(try command(SavePanel(renamed)), from: session, on: host)

      #expect(listed.map { if case .value = $0 { true } else { false } } == true)
      #expect(searched.map { if case .value = $0 { true } else { false } } == true)
      #expect(
        added
          == .failed(
            .invalidRequest(RunPolicy.panel.refusal(AddLink.name))))
      #expect(
        uploaded
          == .failed(
            .invalidRequest(RunPolicy.panel.refusal("upload"))))
      #expect(other == .failed(.invalidRequest("This refresh is of radar; it can save only that panel.")))
      #expect(own == .value(try JSONEncoder().encode(Done())))
      #expect(try await host.run(ListItems()).isEmpty)
      let titles = try await host.panelColumn(of: .chat).slots.compactMap { slot -> String? in
        if case .panel(let panel) = slot { panel.title } else { nil }
      }
      #expect(titles == ["沙箱快讯", "other"])
    }
  }
}
