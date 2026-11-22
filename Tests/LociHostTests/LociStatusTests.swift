import Foundation
import LociModel
import Testing

@testable import LociHost

/// H-S2: the status says what Loci is working on, for the line under its name in the sidebar.
@Suite(.timeLimit(.minutes(1)))
struct LociStatusTests {
  private func working(_ host: LocalHost, on work: LociWork) async -> Bool {
    await value(host.subscribe(LociWorking())) { $0.work == work } != nil
  }

  @Test func anIdleLociIsWorkingOnNothing() async throws {
    try await withHost { host, _, _ in
      #expect(await host.lociStatus() == LociStatus(work: nil))
      #expect(await host.lociStatus().working == false)
    }
  }

  @Test func anAnswerNamesTheToolLociUsedLastWithoutWhatItPrinted() async throws {
    try await withHost(agent: FakeAgent { _ in .readAndHang("notes/firecracker-design.md") }) { host, _, _ in
      _ = try await host.run(SendMessage(to: .main, text: "What did I read?"))

      let status = await value(host.subscribe(LociWorking())) {
        if case .answering(let tool?) = $0.work { tool.kind == .read } else { false }
      }

      guard case .answering(let tool?) = status?.work else {
        Issue.record("no tool in \(String(describing: status))")
        return
      }
      #expect(tool.subject == "notes/firecracker-design.md")
      #expect(tool.output.isEmpty)
      _ = try await host.run(StopTurn(in: .main))
      #expect(await value(host.subscribe(LociWorking())) { !$0.working } != nil)
    }
  }

  @Test func theMainConversationIsNamedBeforeAnItemsConversation() async throws {
    let agent = FakeAgent { prompt in prompt.hasSuffix("main") ? .readAndHang("a.md") : .hang }
    try await withHost(agent: agent) { host, _, _ in
      let item = try await host.run(
        AddTextItem(fileName: "pingora.md", text: ItemConversationTests.article))
      _ = try await host.run(SendMessage(to: .item(item.id), text: "item"))
      _ = try await host.run(SendMessage(to: .main, text: "main"))

      let status = await value(host.subscribe(LociWorking())) {
        if case .answering(let tool?) = $0.work { tool.subject == "a.md" } else { false }
      }

      #expect(status != nil)
      _ = try await host.run(StopTurn(in: .main))
      #expect(await working(host, on: .answering(nil)))
      _ = try await host.run(StopTurn(in: .item(item.id)))
    }
  }

  @Test func aPanelBeingRefreshedIsNamedByItsTitle() async throws {
    try await withHost(agent: PanelRefreshScenarioTests.agent(refreshing: .hang)) { host, _, _ in
      _ = try await host.run(SavePanel(PanelScenarioTests.radar))

      _ = try await host.run(RefreshPanel("radar"))

      #expect(await working(host, on: .refreshing(title: "沙箱雷达")))
      _ = try await host.run(RemovePanel("radar"))
      #expect(await value(host.subscribe(LociWorking())) { !$0.working } != nil)
    }
  }
}
