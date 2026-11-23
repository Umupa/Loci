import AppKit
import Foundation
import LociModel
import Testing

@testable import LociUI

/// P-S17–P-S21: how a panel's items are laid out, edited, taken back and moved.
@MainActor
struct PanelItemTests {
  static func item(
    _ id: String, by: PanelItem.Author = .you, proposed: Bool = false, done: Bool = false, pinned: Bool = false
  ) -> PanelItem {
    PanelItem(id: id, text: id, by: by, proposed: proposed, done: done, pinned: pinned)
  }

  static func week(_ today: [PanelItem], _ week: [PanelItem] = []) -> Panel {
    Panel(
      name: "week", title: "本周待办", follow: "x",
      body: .rows([
        .items(PanelItems(id: "today", name: "今天", adds: true, checks: true, items: today)),
        .items(PanelItems(id: "week", name: "本周", adds: true, checks: true, items: week)),
      ]))
  }

  @Test func pinnedItemsComeFirstAndDoneOnesFoldAway() {
    let section = PanelItems(
      id: "today", checks: true,
      items: [Self.item("a"), Self.item("b", done: true), Self.item("c", pinned: true), Self.item("d", done: true)])

    let shape = SectionShape(section)
    let lingering = SectionShape(section, lingering: ["b"])

    #expect(shape.active.map(\.id) == ["c", "a"])
    #expect(shape.done.map(\.id) == ["b", "d"])
    #expect(lingering.active.map(\.id) == ["c", "a", "b"])
    #expect(lingering.done.map(\.id) == ["d"])
  }

  @Test func theRingCountsTheFirstSectionThatCanBeTicked() {
    let plain = Panel(
      name: "p", title: "p", follow: "x",
      body: .rows([.items(PanelItems(id: "notes", items: [Self.item("x")]))]))

    #expect(CheckProgress(Self.week([Self.item("a", done: true), Self.item("b")])) == CheckProgress(done: 1, all: 2))
    #expect(CheckProgress(Self.week([Self.item("a", done: true)]))?.isFull == true)
    #expect(CheckProgress(Self.week([]))?.isFull == false)
    #expect(CheckProgress(plain) == nil)
  }

  @Test func hiddenLinesAreLeftOutAndPinnedOnesComeFirst() {
    let lines = ["一", "二", "三"].map { PanelListItem(title: $0) }
    let marks = [
      PanelLineKey(lines[0]): PanelLineMark(hidden: true), PanelLineKey(lines[2]): PanelLineMark(pinned: true),
    ]

    #expect(MarkedLines(lines, marks: marks).shown.map(\.line.title) == ["三", "二"])
  }

  @Test func anEditShowsAtOnceAndGivesWayOnceTheHostHasIt() throws {
    let panel = Self.week([Self.item("a")])
    var pending = PendingEdits()
    let edit = PanelEdit.put(Self.item("b"), section: "week", at: nil)

    pending.add(edit)

    #expect(pending.shown(over: panel).sections[1].items.map(\.id) == ["b"])
    pending.settle(on: panel)
    #expect(pending.edits == [edit])
    pending.settle(on: try panel.applying(edit))
    #expect(pending.edits.isEmpty)
  }

  @Test func undoSendsTheEditThatTakesTheLastOneBack() async throws {
    let sent = Sent()
    let editor = PanelEditor()
    let undo = UndoManager()
    undo.groupsByEvent = false
    let panel = Self.week([Self.item("a")])
    editor.settle(on: panel)
    var done = Self.item("a")
    done.done = true

    undo.beginUndoGrouping()
    editor.make(.put(done, section: "today", at: 0), send: sent.send, undoManager: undo)
    undo.endUndoGrouping()
    undo.undo()

    try await sent.count(2)
    #expect(
      sent.all == [.put(done, section: "today", at: 0), .put(Self.item("a"), section: "today", at: 0)])
  }

  @Test func anItemDroppedAmongOthersLandsBesideTheOneItIsDroppedBefore() {
    let section = PanelItems(
      id: "today", checks: true,
      items: [Self.item("a"), Self.item("done", done: true), Self.item("b"), Self.item("c")])
    let moved = Self.item("x")

    #expect(ItemDrop.edit(moved, into: section, at: 0) == .put(moved, section: "today", at: 0))
    #expect(ItemDrop.edit(moved, into: section, at: 1) == .put(moved, section: "today", at: 2))
    #expect(ItemDrop.edit(moved, into: section, at: 3) == .put(moved, section: "today", at: 4))
    #expect(ItemDrop.edit(Self.item("a"), into: section, at: 2) == .put(Self.item("a"), section: "today", at: 3))
    #expect(
      ItemDrop.index(
        at: 55, among: [CGRect(x: 0, y: 0, width: 10, height: 36), CGRect(x: 0, y: 40, width: 10, height: 36)]) == 1)
  }

  @Test func whatRightClickingAnItemOffersDependsOnWhoseItIs() {
    #expect(PanelItemMenu.entries(for: Self.item("a")) == [.pin, .note, .remove])
    #expect(PanelItemMenu.entries(for: Self.item("a", pinned: true)).first == .unpin)
    #expect(PanelItemMenu.entries(for: Self.item("a", by: .loci)) == [.pin, .note, .take, .remove])
    #expect(PanelLineMenu.entries(for: PanelLineMark(pinned: true, note: "x")) == [.unpin, .editNote, .hide])
  }

  /// The dragged item's row stays in the section, unseen, while its hollow shows where it would land: a row
  /// taken out mid-drag takes its drag with it, and the panel's own drag would carry on in its place.
  @Test func theDraggedItemKeepsItsRowWhileItsHollowMoves() {
    let section = PanelItems(id: "today", checks: true, items: [Self.item("a"), Self.item("b"), Self.item("c")])
    let shape = SectionShape(section)

    let within = SectionRows(shape, carrying: "c", hollow: 0)
    let away = SectionRows(shape, carrying: "c", hollow: nil)
    let arriving = SectionRows(shape, carrying: "x", hollow: 3)

    #expect(within.rows == [.hollow, .item(Self.item("a")), .item(Self.item("b")), .carried(Self.item("c"))])
    #expect(away.rows == [.item(Self.item("a")), .item(Self.item("b")), .carried(Self.item("c"))])
    #expect(arriving.rows.last == .hollow)
    #expect(SectionRows(shape, carrying: nil, hollow: nil).rows.count == 3)
  }

  static func carrying(_ carry: ItemCarry) {
    carry.report(section: "today", at: CGRect(x: 0, y: 0, width: 300, height: 200))
    carry.report(row: "a", in: "today", at: CGRect(x: 0, y: 20, width: 300, height: 36))
    carry.report(row: "b", in: "today", at: CGRect(x: 0, y: 60, width: 300, height: 36))
    carry.move(Self.item("b"), checks: true, from: CGPoint(x: 10, y: 70), to: CGPoint(x: 10, y: 30))
  }

  @Test func aDragLandsWhereItWasLetGoAndLeavesNothingBehind() throws {
    let carry = ItemCarry()
    Self.carrying(carry)

    let landing = try #require(carry.end())

    #expect(landing.target == ItemCarry.Target(section: "today", index: 0))
    #expect(carry.carried == nil)
  }

  @Test func escapeCallsTheDragOffAndTheRestOfItIsIgnored() {
    let carry = ItemCarry()
    Self.carrying(carry)

    carry.listen(escape: true, buttonDown: true)
    carry.move(Self.item("b"), checks: true, from: CGPoint(x: 10, y: 70), to: CGPoint(x: 10, y: 40))

    #expect(carry.carried == nil)
    #expect(carry.end() == nil)
    Self.carrying(carry)
    #expect(carry.carried != nil)
  }

  @Test func aDragWhoseEndNeverCameIsCalledOffOnceTheButtonIsUp() {
    let carry = ItemCarry()
    Self.carrying(carry)

    for _ in 0..<ItemCarry.releaseGrace - 1 { carry.listen(escape: false, buttonDown: false) }
    #expect(carry.carried != nil)
    carry.listen(escape: false, buttonDown: false)

    #expect(carry.carried == nil)
    #expect(carry.end() == nil)
  }

  @Test func anItemBeingTypedInIsNotDragged() {
    #expect(ItemTyping.none.takesDrags)
    #expect(!ItemTyping.words("读完").takesDrags)
    #expect(!ItemTyping.note("").takesDrags)
  }

  @Test func onlyLociSItemsThatAreNewToThePanelArriveRinged() {
    let before = Self.week([Self.item("a")])
    let after = Self.week([Self.item("a"), Self.item("b"), Self.item("kata", by: .loci)])

    #expect(Arrivals.new(in: after, since: before) == ["kata"])
    #expect(Arrivals.new(in: after, since: nil).isEmpty)
  }
}

/// The edits a panel sent, in order.
@MainActor
final class Sent {
  private(set) var all: [PanelEdit] = []

  func send(_ edit: PanelEdit) async -> Bool {
    all.append(edit)
    return true
  }

  func count(_ count: Int) async throws {
    for _ in 0..<200 where all.count < count { try await Task.sleep(for: .milliseconds(5)) }
  }
}
