import Foundation
import Testing

@testable import LociModel

/// P-S17, P-S18, P-S22: a stretch of items Loci sets up and the person writes in, read from the panel file and
/// checked like the rest of it.
struct PanelItemsTests {
  static func item(
    _ id: String, _ text: String, by: PanelItem.Author = .loci, proposed: Bool = false, done: Bool = false,
    pinned: Bool = false, note: String? = nil, why: String? = nil
  ) -> PanelItem {
    PanelItem(id: id, text: text, by: by, proposed: proposed, done: done, pinned: pinned, note: note, why: why)
  }

  /// 「本周待办」: today and this week, both open to adding and ticking.
  static func week(today: [PanelItem], week: [PanelItem] = []) -> Panel {
    Panel(
      name: "week", title: "本周待办", follow: "这周要做的事",
      body: .rows([
        .items(PanelItems(id: "today", name: "今天", adds: true, checks: true, items: today)),
        .items(PanelItems(id: "week", name: "本周", adds: true, checks: true, items: week)),
      ]))
  }

  @Test func itemsReadFromTheJSONLociWritesAndAreLociSUnlessTheySayOtherwise() throws {
    let json = """
      { "title": "本周待办", "follow": "这周要做的事", "rows": [
        { "row": "items", "id": "today", "name": "今天", "adds": true, "checks": true, "items": [
          { "id": "kata", "text": "回 Kata 的 review", "proposed": true, "why": "你说周五前" },
          { "id": "cat", "text": "买猫粮", "by": "you", "done": true, "pinned": true, "note": "大袋" }
        ] }
      ] }
      """

    let panel = try PanelCheck.read(Data(json.utf8), name: "week")

    #expect(
      panel.sections == [
        PanelItems(
          id: "today", name: "今天", adds: true, checks: true,
          items: [
            Self.item("kata", "回 Kata 的 review", proposed: true, why: "你说周五前"),
            Self.item("cat", "买猫粮", by: .you, done: true, pinned: true, note: "大袋"),
          ])
      ])
  }

  @Test func whatIsFalseOrMissingIsLeftOutOfTheFile() throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let row = PanelRow.items(PanelItems(id: "week", items: [Self.item("a", "压测")]))

    #expect(
      String(decoding: try encoder.encode(row), as: UTF8.self)
        == #"{"id":"week","items":[{"id":"a","text":"压测"}],"row":"items"}"#)
    #expect(try HostCodingTests.roundTrips(Self.week(today: [Self.item("b", "读完", by: .you, note: "第三节")])))
  }

  @Test func aPanelOfItemsNeedNotStartWithASentence() {
    #expect(PanelCheck.problems(in: Self.week(today: [])).isEmpty)
  }

  @Test func sectionAndItemIdsAreGivenAndUsedOnceInThePanel() {
    let json = """
      { "title": "a", "follow": "b", "pages": [
        { "name": "One", "rows": [
          { "row": "items", "id": "today", "items": [{ "id": "a", "text": "一" }, { "id": " ", "text": "二" }] }
        ] },
        { "name": "Two", "rows": [
          { "row": "items", "id": "today", "items": [{ "id": "a", "text": "三" }] },
          { "row": "items", "id": "", "name": " ", "items": [{ "id": "c", "text": "" }] }
        ] }
      ] }
      """

    #expect(
      PanelCheckTests.problems(json) == [
        "pages[0].rows[0].items[1].id: is empty",
        #"pages[1].rows[0].id: "today" is used by an earlier section"#,
        #"pages[1].rows[0].items[0].id: "a" is used by an earlier item"#,
        "pages[1].rows[1].id: is empty",
        "pages[1].rows[1].name: is empty; leave it out for a section without a name",
        "pages[1].rows[1].items[0].text: is empty",
      ])
  }

  @Test func onlyLociSItemsCarryAProposalOrAWhy() {
    let rows = """
      { "row": "items", "id": "today", "items": [
        { "id": "a", "text": "一", "by": "you", "proposed": true, "why": "因为" },
        { "id": "b", "text": "二", "why": " ", "note": "" }
      ] }
      """

    #expect(
      PanelCheckTests.problems(PanelCheckTests.panel(rows: rows)) == [
        "rows[0].items[0].proposed: only Loci's items are proposed",
        "rows[0].items[0].why: only Loci's items say why",
        "rows[0].items[1].note: is empty; leave it out",
        "rows[0].items[1].why: is empty; leave it out",
      ])
  }

  @Test func anItemsRowNamesWhatItCanBe() {
    #expect(
      PanelCheckTests.problems(
        PanelCheckTests.panel(
          rows: #"{ "row": "items", "id": "a", "items": [{ "id": "x", "text": "t", "by": "them" }] }"#))
        == [#"rows[0].items[0].by: is not one of the values it can be: you, loci"#])
  }
}
