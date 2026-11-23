import Foundation
import Testing

@testable import LociModel

/// P-S18, P-S19: one edit at a time, each with the edit that takes it back.
struct PanelEditTests {
  static let read = PanelItemsTests.item("read", "读完逃逸链复盘", by: .you)
  static let notes = PanelItemsTests.item("notes", "整理面试笔记")
  static let bench = PanelItemsTests.item("bench", "冷启动压测", by: .you)
  static let panel = PanelItemsTests.week(today: [read, notes], week: [bench])

  static func texts(_ panel: Panel) -> [[String]] {
    panel.sections.map { $0.items.map(\.text) }
  }

  @Test func aNewItemGoesWhereItIsPutOrAtTheEnd() throws {
    let cat = PanelItemsTests.item("cat", "买猫粮", by: .you)

    #expect(
      try Self.texts(Self.panel.applying(.put(cat, section: "today", at: 1))) == [
        ["读完逃逸链复盘", "买猫粮", "整理面试笔记"], ["冷启动压测"],
      ])
    #expect(
      try Self.texts(Self.panel.applying(.put(cat, section: "week", at: nil))) == [
        ["读完逃逸链复盘", "整理面试笔记"], ["冷启动压测", "买猫粮"],
      ])
    #expect(try Self.texts(Self.panel.applying(.put(cat, section: "week", at: 9))).last == ["冷启动压测", "买猫粮"])
  }

  @Test func puttingAnItemAgainReplacesItAndMovesItEvenToAnotherSection() throws {
    var bench = Self.bench
    bench.done = true

    let moved = try Self.panel.applying(.put(bench, section: "today", at: 0))

    #expect(Self.texts(moved) == [["冷启动压测", "读完逃逸链复盘", "整理面试笔记"], []])
    #expect(moved.sections[0].items[0].done)
  }

  @Test func removingTakesTheItemOut() throws {
    #expect(try Self.texts(Self.panel.applying(.remove("notes"))) == [["读完逃逸链复盘"], ["冷启动压测"]])
  }

  @Test func anEditThatHasNoPlaceIsRefused() {
    #expect(throws: PanelProblems.self) { try Self.panel.applying(.put(Self.read, section: "later", at: nil)) }
    #expect(throws: PanelProblems.self) { try Self.panel.applying(.remove("gone")) }
  }

  @Test(arguments: [
    PanelEdit.put(PanelItemsTests.item("cat", "买猫粮", by: .you), section: "week", at: 0),
    PanelEdit.put(PanelItemsTests.item("read", "读完复盘", by: .you), section: "week", at: 1),
    PanelEdit.put(PanelItemsTests.item("notes", "整理面试笔记", pinned: true), section: "today", at: 0),
    PanelEdit.remove("read"),
  ])
  func everyEditHasOneThatTakesItBack(edit: PanelEdit) throws {
    let back = try #require(edit.reverse(in: Self.panel))

    #expect(try Self.panel.applying(edit).applying(back) == Self.panel)
  }

  @Test func editsSurviveTheWire() throws {
    #expect(try HostCodingTests.roundTrips(EditPanel("week", .put(Self.read, section: "today", at: 0))))
    #expect(try HostCodingTests.roundTrips(EditPanel("week", .remove("read"))))
    let key = PanelLineKey(PanelListItem(title: "HN 热议", link: URL(string: "https://news.ycombinator.com/item?id=1")))
    #expect(try HostCodingTests.roundTrips(MarkPanelLine("radar", key, PanelLineMark(pinned: true, note: "看评论"))))
    #expect(
      try HostCodingTests.roundTrips(PanelColumn(slots: [], marks: ["radar": [key: PanelLineMark(hidden: true)]])))
  }

  @Test func aListLineIsKnownByItsLinkOrElseItsTitle() {
    let link = URL(string: "https://github.com/x/y/pull/1")
    #expect(PanelLineKey(PanelListItem(title: "a", link: link)) == PanelLineKey(PanelListItem(title: "b", link: link)))
    #expect(PanelLineKey(PanelListItem(title: "a")) == PanelLineKey(PanelListItem(title: "a", subtitle: "x")))
    #expect(PanelLineKey(PanelListItem(title: "a")) != PanelLineKey(PanelListItem(title: "b")))
  }
}
