import Foundation
import LociModel
import LociStore
import Testing

@testable import LociHost

/// P-S5, P-S7, P-S9: the panel column, as the host serves it.
@Suite(.timeLimit(.minutes(1)))
struct PanelScenarioTests {
  static let radar = Panel(
    name: "radar", title: "沙箱雷达", sources: ["github.com"], follow: "盯着 CubeSandbox 的新版本",
    refresh: PanelRefresh(every: .day, at: "10:00"), body: .rows([.sentence("**v0.8.0** 发布。")]))

  static func panel(_ name: String, title: String? = nil) -> Panel {
    Panel(name: name, title: title ?? name, follow: "x", body: .rows([.sentence("a")]))
  }

  static func names(_ column: PanelColumn) -> [String] {
    column.slots.map { slot in
      switch slot {
      case .reading: "接着读"
      case .panel(let panel): panel.name
      }
    }
  }

  @Test func aSavedPanelAppearsAtTheBottomOfTheColumn() async throws {
    try await withHost { host, place, _ in
      _ = try await host.run(SavePanel(Self.panel("a")))
      _ = try await host.run(SavePanel(Self.radar))
      _ = try await host.run(SavePanel(Self.panel("a", title: "changed")))

      let column = try await host.panelColumn()

      #expect(Self.names(column) == ["a", "radar"])
      #expect(column.slots.last == .panel(Self.radar))
      #expect(FileManager.default.fileExists(atPath: place.root.appending(path: "agent/panels/radar.json").path()))
    }
  }

  @Test func aPanelThatCannotBeShownIsRefusedWithEveryProblem() async throws {
    try await withHost { host, place, _ in
      let broken = Panel(name: "radar", title: "", follow: "x", body: .rows([.label("a")]))

      await #expect(
        throws: HostError.invalidRequest(
          "title: is empty\nrows[0]: the first row must be a sentence that sums the panel up")
      ) {
        _ = try await host.run(SavePanel(broken))
      }
      #expect(!FileManager.default.fileExists(atPath: place.root.appending(path: "agent/panels").path()))
    }
  }

  @Test func aFileBrokenByHandLeavesThePanelAsItWas() async throws {
    try await withHost { host, place, _ in
      _ = try await host.run(SavePanel(Self.radar))
      let file = place.root.appending(path: "agent/panels/radar.json")

      try Data(#"{ "title": "沙箱雷达", "follow": "x", "rows": [{ "row": "bars", "bars": [] }] }"#.utf8).write(to: file)

      #expect(try await host.panelColumn().slots == [.panel(Self.radar)])
      let entries = try await host.run(ListPanels())
      #expect(entries.map(\.panel) == [Self.radar])
      #expect(
        entries.first?.problems.map(\.description) == [
          "rows[0]: the first row must be a sentence that sums the panel up", "rows[0].bars: is empty",
        ])
    }
  }

  @Test func aFileThatNeverCouldBeShownIsNotInTheColumn() async throws {
    try await withHost { host, place, _ in
      try place.store.savePanel(Self.radar)
      try Data("{".utf8).write(to: place.root.appending(path: "agent/panels/half.json"))

      #expect(Self.names(try await host.panelColumn()) == ["radar"])
      #expect(try await host.run(ListPanels()).map(\.name) == ["half", "radar"])
    }
  }

  @Test func aPanelEditedByHandReachesTheColumn() async throws {
    try await withHost { host, place, _ in
      _ = try await host.run(SavePanel(Self.radar))
      let column = host.subscribe(WatchPanelColumn())
      _ = await value(column) { !$0.slots.isEmpty }

      try place.edit(place.root.appending(path: "agent/panels/radar.json")) {
        $0.replacing("沙箱雷达", with: "沙箱快讯")
      }

      let edited = await value(column) { column in
        column.slots.contains { if case .panel(let panel) = $0 { panel.title == "沙箱快讯" } else { false } }
      }
      #expect(edited != nil)
    }
  }

  @Test func movingToTheTopAndRemovingKeepTheRestInOrder() async throws {
    try await withHost { host, place, _ in
      for name in ["a", "b", "c"] { _ = try await host.run(SavePanel(Self.panel(name))) }

      _ = try await host.run(MovePanelToTop(.panel("c")))
      _ = try await host.run(RemovePanel("a"))

      #expect(Self.names(try await host.panelColumn()) == ["c", "b"])
      #expect(!FileManager.default.fileExists(atPath: place.root.appending(path: "agent/panels/a.json").path()))
      await #expect(throws: HostError.self) { _ = try await host.run(RemovePanel("a")) }
      await #expect(throws: HostError.notFound("zzz")) { _ = try await host.run(MovePanelToTop(.panel("zzz"))) }
    }
  }

  @Test func readingNowListsWhatIsReadPartwayMostRecentFirstAndCanMoveToTheTop() async throws {
    try await withHost { host, _, world in
      #expect(Self.names(try await host.panelColumn()) == [])
      _ = try await host.run(SavePanel(Self.radar))
      let first = try await host.run(AddTextItem(fileName: "a.md", text: "# Borg\n\nOne. Two. Three. Four.\n"))
      let second = try await host.run(
        AddTextItem(fileName: "b.md", text: "# Omega\n\n" + String(repeating: "调度。", count: 300)))
      let finished = try await host.run(AddTextItem(fileName: "c.md", text: "# Done\n\nAll of it.\n"))
      try await read(host, first, at: "Three.")
      world.advance(minutes: 1)
      try await read(host, second, at: "调度。")
      try await read(host, finished, at: "All of it.")
      _ = try await host.run(MarkRead(content: .item(finished.id)))

      let column = try await host.panelColumn()

      #expect(Self.names(column) == ["接着读", "radar"])
      guard case .reading(let reading) = column.slots.first else { return }
      #expect(reading.map(\.item.id) == [second.id, first.id])
      #expect(reading[1].progress > 0.5 && reading[1].progress < 1)
      #expect(reading[0].minutesLeft == 2)
      _ = try await host.run(MovePanelToTop(.panel("radar")))
      #expect(Self.names(try await host.panelColumn()) == ["radar", "接着读"])
    }
  }

  @Test func readingNowAppearsAsSoonAsAPositionIsSaved() async throws {
    try await withHost { host, _, _ in
      let item = try await host.run(AddTextItem(fileName: "a.md", text: "# Borg\n\nOne. Two. Three. Four.\n"))
      try await Task.sleep(for: .milliseconds(300))
      let column = host.subscribe(WatchPanelColumn())
      #expect(try await host.panelColumn().slots.isEmpty)

      try await read(host, item, at: "Three.")

      let shown = await value(column) { !$0.slots.isEmpty }
      #expect(shown?.slots.first.flatMap(Self.reading)?.map(\.item.id) == [item.id])
    }
  }

  static func reading(_ slot: PanelSlot) -> [ReadingNow]? {
    guard case .reading(let reading) = slot else { return nil }
    return reading
  }

  private func read(_ host: LocalHost, _ item: Item, at words: String) async throws {
    let position = Locator.item(item.id, .quote(try TextQuote(words, before: " ")))
    _ = try await host.run(SaveReadingPosition(content: .item(item.id), position: position))
  }
}
