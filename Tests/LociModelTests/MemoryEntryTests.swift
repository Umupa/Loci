import Testing

@testable import LociModel

struct MemoryEntryTests {
  static let link = "loci://library/\(Fixture.item)#quote=term"
  static func entries(_ text: String) -> [Line<MemoryEntry>] {
    MemoryEntry.lines(of: text, title: { $0 == Fixture.item ? "Raft" : nil })
  }

  /// ME-S1, ME-S2: an index line links to the page holding its detail.
  @Test func anIndexLineLinksToItsWikiPageAndKeepsItsSource() throws {
    let line = "- 2026-11-12 Raft 的 term 和 index 混过两次 [Raft](memory/raft.md) \(Self.link)"
    let entry = try #require(Self.entries(line).first)
    guard case .entry(let read) = entry else { throw ModelError("not an entry") }

    #expect(read.text == "Raft 的 term 和 index 混过两次")
    #expect(read.page == WikiLink(name: "raft", title: "Raft"))
    #expect(read.source?.itemTitle == "Raft")
  }

  @Test func everyLinkToAPageIsFoundFromTheIndexOrFromAnotherPage() {
    let text = "- a [Raft](memory/raft.md)\n- b [沙箱](sandboxes.md) [Raft](raft.md)\n- c [x](https://x.md)"

    #expect(WikiLink.all(in: text).map(\.name) == ["raft", "sandboxes", "raft"])
    #expect(WikiLink.isName("raft-notes") && !WikiLink.isName("Raft") && !WikiLink.isName("../x"))
  }

  @Test func anEntryHasAnOptionalDayAndItsWords() {
    #expect(
      Self.entries("# Memory\n\n- 2026-11-02 先给结论\n- 不要出题考") == [
        .entry(MemoryEntry(day: Day("2026-11-02"), text: "先给结论", source: nil, line: "- 2026-11-02 先给结论")),
        .entry(MemoryEntry(day: nil, text: "不要出题考", source: nil, line: "- 不要出题考")),
      ])
  }

  @Test func aBareLinkBecomesTheSourceAndLeavesTheWords() throws {
    let line = "- 2026-11-12 Mixed up term and index. \(Self.link)"
    guard case .entry(let entry) = try #require(Self.entries(line).first) else { throw ModelError("no entry") }

    #expect(entry.text == "Mixed up term and index.")
    #expect(entry.source == .init(locator: try #require(Locator(Self.link)), itemTitle: "Raft"))
  }

  @Test func aMarkdownLinkLeavesItsWordsInTheText() throws {
    guard case .entry(let entry) = try #require(Self.entries("- stuck at [the third part](\(Self.link)) twice").first)
    else { throw ModelError("no entry") }

    #expect(entry.text == "stuck at the third part twice")
    #expect(entry.source?.locator == Locator(Self.link))
  }

  @Test func punctuationAfterABareLinkIsNotPartOfIt() throws {
    let link = "loci://library/\(Fixture.item)#t=204.1,207.8"
    guard case .entry(let entry) = try #require(Self.entries("- 那段 \(link)，讲得最清楚").first) else {
      throw ModelError("no entry")
    }

    #expect(entry.source?.locator == Locator(link))
    #expect(entry.text == "那段 ，讲得最清楚")
  }

  @Test func aSourceWhoseItemIsGoneHasNoTitle() throws {
    let link = "loci://library/\(Fixture.id(9))#t=1"
    guard case .entry(let entry) = try #require(Self.entries("- x \(link)").first) else { throw ModelError("no entry") }

    #expect(entry.source?.itemTitle == nil)
  }

  @Test func indentedLinesContinueTheEntryAbove() throws {
    guard case .entry(let entry) = try #require(Self.entries("- 第一行\n  第二行\n- 下一条").first) else {
      throw ModelError("no entry")
    }

    #expect(entry.text == "第一行\n第二行")
    #expect(entry.line == "- 第一行")
  }

  @Test func otherLinesAndSubheadingsShowAsWritten() {
    #expect(Self.entries("## 学习\nloose words\n- \n") == [.text("## 学习"), .text("loose words"), .text("- ")])
  }

  @Test func forgettingRemovesTheEntryAndItsContinuationsOnly() {
    let text = "# Memory\n- a\n  more a\n- b\n"

    #expect(MemoryEntry.removing("- a", from: text) == "# Memory\n- b\n")
    #expect(MemoryEntry.removing("- c", from: text) == nil)
  }
}
