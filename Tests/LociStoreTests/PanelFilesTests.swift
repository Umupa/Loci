import Foundation
import LociModel
import Testing

@testable import LociStore

/// `agent/panels/<name>.json` and what the app keeps beside them.
struct PanelFilesTests {
  static let panel = Panel(
    name: "sandbox-radar", title: "沙箱雷达", sources: ["github.com"], follow: "盯着新版本",
    refresh: PanelRefresh(every: .day, at: "10:00"), body: .rows([.sentence("**v0.8.0** 发布。")]))

  @Test func aSavedPanelReadsBackUnderItsFilesName() throws {
    try withStore { store in
      try store.home(.chat).savePanel(Self.panel)
      try FileManager.default.moveItem(
        at: store.root.appending(path: "agent/panels/sandbox-radar.json"),
        to: store.root.appending(path: "agent/panels/radar.json"))

      let entries = store.home(.chat).panels()

      #expect(entries.map(\.name) == ["radar"])
      #expect(entries.first?.panel?.name == "radar" && entries.first?.panel?.title == "沙箱雷达")
      #expect(entries.first?.problems == [])
    }
  }

  @Test func aBrokenFileSaysWhatIsWrongWithIt() throws {
    try withStore { store in
      try store.writeFile("agent/panels/radar.json", #"{ "title": "", "follow": "x", "rows": [] }"#)
      try store.writeFile("agent/panels/notes.txt", "not a panel")

      #expect(
        store.home(.chat).panels() == [
          PanelEntry(
            name: "radar", panel: nil,
            problems: [PanelProblem("title", "is empty"), PanelProblem("rows", "has no rows")])
        ])
    }
  }

  @Test func aFileBrokenLaterStillShowsItsLastGoodPanelInAStoreOpenedAfresh() throws {
    try withStore { store in
      try store.home(.chat).savePanel(Self.panel)
      _ = store.home(.chat).panels()
      try store.writeFile("agent/panels/sandbox-radar.json", "{ broken")

      let reopened = Store(root: store.root, discard: .permanently)

      #expect(reopened.home(.chat).panels().map(\.panel) == [Self.panel])
      #expect(reopened.home(.chat).panels().first?.problems == [PanelProblem("", "is not JSON")])
    }
  }

  @Test func theLastGoodCopyIsKeptWhereLociDoesNotLook() throws {
    try withStore { store in
      try store.home(.chat).savePanel(Self.panel)
      _ = store.home(.chat).panels()

      let agentFiles = FileManager.default.subpaths(atPath: store.root.appending(path: "agent").path()) ?? []

      #expect(agentFiles.filter { $0.hasSuffix(".json") } == ["panels/sandbox-radar.json"])
    }
  }

  @Test func removingAPanelDeletesItsFileAndItsCopy() throws {
    try withStore { store in
      try store.home(.chat).savePanel(Self.panel)
      _ = store.home(.chat).panels()

      try store.home(.chat).removePanel(named: "sandbox-radar")
      try store.writeFile("agent/panels/sandbox-radar.json", "{ broken")

      #expect(store.home(.chat).panels().map(\.panel) == [nil])
      #expect(throws: StoreError.self) { try store.home(.chat).removePanel(named: "other") }
    }
  }

  @Test func aCopyWhoseFileIsGoneIsForgotten() throws {
    try withStore { store in
      try store.home(.chat).savePanel(Self.panel)
      _ = store.home(.chat).panels()
      try FileManager.default.removeItem(at: store.root.appending(path: "agent/panels/sandbox-radar.json"))

      #expect(store.home(.chat).panels().isEmpty)
      try store.writeFile("agent/panels/sandbox-radar.json", "{ broken")
      #expect(store.home(.chat).panels().map(\.panel) == [nil])
    }
  }

  @Test func theOrderAndRefreshTimesAreKeptOutsideThePanelFiles() throws {
    try withStore { store in
      #expect(store.home(.chat).panelState() == PanelState())

      try store.home(.chat).changePanelState { state in
        state.order = [.panel("sandbox-radar"), .reading]
        state.refreshed["sandbox-radar"] = Fixture.instant
      }

      #expect(store.home(.chat).panelState().order == [.panel("sandbox-radar"), .reading])
      #expect(store.home(.chat).panelState().refreshed == ["sandbox-radar": Fixture.instant])
      #expect(store.home(.chat).panels().isEmpty)
      try store.writeFile("panels.json", "{ broken")
      #expect(store.home(.chat).panelState() == PanelState())
    }
  }

  @Test func onlyContentWithAPositionAndNotFinishedIsReadPartwayNewestFirst() throws {
    let database = try StoreDatabase.inMemory()
    let (older, newer, finished, unplaced) = (Fixture.id(2), Fixture.id(3), Fixture.id(4), Fixture.id(5))
    func at(_ minutes: Int64) -> Timestamp {
      Timestamp(millisecondsSince1970: Fixture.instant.millisecondsSince1970 + minutes * 60_000)
    }
    func place(_ item: EntityID) throws -> Locator { .item(item, .time(try TimeSpan(start: .seconds(30)))) }
    try database.save(ReadingState(position: try place(older), finished: false, updatedAt: at(1)), for: .item(older))
    try database.save(ReadingState(position: try place(newer), finished: false, updatedAt: at(2)), for: .item(newer))
    try database.save(
      ReadingState(position: try place(finished), finished: true, updatedAt: at(3)), for: .item(finished))
    try database.save(ReadingState(position: nil, finished: false, updatedAt: at(4)), for: .item(unplaced))

    let partway = try database.readingPartway()

    #expect(partway.map(\.content) == [.item(newer), .item(older)])
    #expect(partway.first?.state.position == (try place(newer)))
  }

  static func at(days: Int64) -> Timestamp {
    Timestamp(millisecondsSince1970: 1_763_100_000_000 + days * 24 * 3_600_000)
  }

  @Test func itemsThePersonRemovedAreRememberedForAWhile() {
    var state = PanelState()

    state.remember(removed: "kata", from: "week", at: Self.at(days: 0))
    state.remember(removed: "lin", from: "week", at: Self.at(days: 5))

    #expect(state.removed(from: "week", now: Self.at(days: 6)) == ["kata", "lin"])
    #expect(state.removed(from: "week", now: Self.at(days: 10)) == ["lin"])
    #expect(state.removed(from: "radar", now: Self.at(days: 6)).isEmpty)
  }

  @Test func onlyTheLatestRemovalsAreKept() throws {
    var state = PanelState()

    for index in 0..<(PanelState.removalsKept + 10) {
      state.remember(removed: "i\(index)", from: "week", at: Self.at(days: 0))
    }

    #expect(state.removed(from: "week", now: Self.at(days: 0)).count == PanelState.removalsKept)
    #expect(!state.removed(from: "week", now: Self.at(days: 0)).contains("i0"))
    state.remember(removed: "late", from: "week", at: Self.at(days: 30))
    #expect(try #require(state.removals["week"]).map(\.id) == ["late"])
  }
}
