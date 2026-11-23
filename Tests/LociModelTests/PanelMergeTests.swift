import Foundation
import Testing

@testable import LociModel

/// P-S17, P-S22: whatever Loci saves, the person's items and the person's take on every item stay.
struct PanelMergeTests {
  typealias I = PanelItemsTests

  static let mine = I.item("mine", "读完逃逸链复盘", by: .you, pinned: true, note: "第三节")
  static let ticked = I.item("ticked", "买猫粮", by: .you, done: true)
  static let lociS = I.item("loci", "整理面试笔记", pinned: true, note: "周四前", why: "你昨天说的")
  static let current = I.week(today: [mine, lociS, ticked], week: [I.item("bench", "冷启动压测")])

  static func saved(today: [PanelItem], week: [PanelItem] = []) -> Panel {
    I.week(today: today, week: week)
  }

  @Test func thePersonSItemsLeftOutArePutBackWhereTheyWere() throws {
    let merged = try PanelMerge.loci(Self.saved(today: [I.item("new", "新的一条")]), onto: Self.current)

    #expect(merged.sections[0].items.map(\.id) == ["mine", "new", "ticked"])
    #expect(merged.sections[0].items[0] == Self.mine)
  }

  @Test func thePersonSWordsAndOwnershipComeBackButLociMayMoveAndTickThem() throws {
    var changed = Self.mine
    changed.text = "读完了"
    changed.by = .loci
    changed.done = true
    changed.pinned = false
    changed.note = nil

    let merged = try PanelMerge.loci(Self.saved(today: [Self.ticked], week: [changed]), onto: Self.current)

    var expected = Self.mine
    expected.done = true
    #expect(merged.sections[1].items == [expected])
    #expect(merged.sections[0].items == [Self.ticked])
  }

  @Test func theTakeOnEveryItemIsKeptAndATickStays() throws {
    var plain = Self.lociS
    plain.text = "整理沙箱面试笔记"
    plain.pinned = false
    plain.note = "伙伴写的"
    plain.why = "换了个说法"
    var unticked = Self.ticked
    unticked.done = false

    let merged = try PanelMerge.loci(Self.saved(today: [Self.mine, plain, unticked]), onto: Self.current)

    #expect(
      merged.sections[0].items[1]
        == I.item("loci", "整理沙箱面试笔记", pinned: true, note: "周四前", why: "换了个说法"))
    #expect(merged.sections[0].items[2].done)
  }

  @Test func lociCannotPinOrNoteANewItemNorClaimOneAsThePersons() throws {
    let saved = Self.saved(
      today: [Self.mine, Self.ticked, I.item("new", "新", pinned: true, note: "x"), I.item("forged", "伪造", by: .you)])

    let merged = try PanelMerge.loci(saved, onto: Self.current)

    #expect(merged.sections[0].items.map(\.id) == ["mine", "ticked", "new"])
    #expect(merged.sections[0].items[2] == I.item("new", "新"))
  }

  @Test func aSectionHoldingThePersonSItemsCannotBeDropped() {
    let saved = Panel(
      name: "week", title: "本周待办", follow: "这周要做的事",
      body: .rows([.items(PanelItems(id: "week", name: "本周", adds: true, checks: true, items: []))]))

    #expect(throws: PanelProblems.self) { try PanelMerge.loci(saved, onto: Self.current) }
  }

  @Test func aNewPanelHasOnlyLociSItems() throws {
    let saved = Self.saved(today: [I.item("a", "一", by: .you, pinned: true, note: "x")])

    let merged = try PanelMerge.loci(saved, onto: nil)

    #expect(merged.sections[0].items == [I.item("a", "一")])
  }

  @Test func lociCannotRemoveOrRewordThePersonSItemsOneAtATime() throws {
    #expect(throws: PanelProblems.self) { try PanelMerge.loci(.remove("mine"), on: Self.current) }
    var reworded = Self.mine
    reworded.text = "别的"
    #expect(throws: PanelProblems.self) {
      try PanelMerge.loci(.put(reworded, section: "today", at: nil), on: Self.current)
    }
  }

  @Test func lociMayMoveAndTickThePersonSItemsOneAtATime() throws {
    var moved = I.item("mine", "读完逃逸链复盘", done: true)

    let edit = try PanelMerge.loci(.put(moved, section: "week", at: 0), on: Self.current)

    moved = Self.mine
    moved.done = true
    #expect(edit == .put(moved, section: "week", at: 0))
    #expect(try PanelMerge.loci(.remove("loci"), on: Self.current) == .remove("loci"))
  }

  @Test func whatLociAddsOneAtATimeIsLociS() throws {
    let edit = try PanelMerge.loci(
      .put(I.item("new", "新", by: .you, pinned: true, note: "x"), section: "week", at: nil), on: Self.current)

    #expect(edit == .put(I.item("new", "新"), section: "week", at: nil))
  }

  @Test func lociSItemsThePersonRemovedDoNotComeBackWithAnOldCopy() throws {
    let current = I.week(today: [Self.mine, Self.ticked], week: [])
    let old = Self.saved(today: [Self.mine, Self.lociS, Self.ticked], week: [I.item("bench", "冷启动压测")])

    let merged = try PanelMerge.loci(old, onto: current, removed: ["loci", "bench"])

    #expect(merged.sections.map { $0.items.map(\.id) } == [["mine", "ticked"], []])
  }
}
