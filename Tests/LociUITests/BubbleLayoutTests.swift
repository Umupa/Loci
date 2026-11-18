import Testing

@testable import LociUI

struct BubbleLayoutTests {
  @Test func aReplyIsSentAsOneBubbleForEachParagraph() {
    #expect(BubbleLayout.bubbles(in: "早\n\n图画好了，挂在 Pingora 第二条划线旁边") == ["早", "图画好了，挂在 Pingora 第二条划线旁边"])
  }

  @Test func linesWithNoBlankBetweenThemStayInOneBubble() {
    #expect(BubbleLayout.bubbles(in: "## 结论\n不划算\n\n理由在下面") == ["## 结论\n不划算", "理由在下面"])
  }

  @Test func aCodeBlockStaysWholeWithItsBlankLines() {
    let code = "```swift\nlet a = 1\n\nlet b = 2\n```"
    #expect(BubbleLayout.bubbles(in: "看这段\n\n\(code)\n\n就这样") == ["看这段", code, "就这样"])
  }

  @Test func aLooseListStaysWhole() {
    let list = "- 一\n\n- 二\n\n- 三"
    #expect(BubbleLayout.bubbles(in: "三点\n\n\(list)") == ["三点", list])
  }

  @Test func aTableAndAQuoteEachStayWhole() {
    let table = "| a | b |\n|---|---|\n| 1 | 2 |"
    let quote = "> 一句\n>\n> 又一句"
    #expect(BubbleLayout.bubbles(in: "\(table)\n\n\(quote)") == [table, quote])
  }

  @Test func aFormulaWithBlankLinesInsideStaysWhole() {
    let bubbles = BubbleLayout.bubbles(in: "公式：\n\n$$\na + b\n\nc\n$$")
    #expect(bubbles.count == 2)
    #expect(bubbles.last?.contains("a + b") == true)
    #expect(bubbles.last?.contains("c") == true)
  }

  @Test func aReplyStillStreamingGrowsInItsLastBubble() {
    #expect(BubbleLayout.bubbles(in: "先说结论\n\n不划算，因为") == ["先说结论", "不划算，因为"])
    #expect(BubbleLayout.bubbles(in: "先说结论\n\n```\nlet a") == ["先说结论", "```\nlet a"])
  }

  @Test func onlyTheLastBubbleOfARunCarriesTheFace() {
    let positions = BubbleLayout.positions([.person, .loci, .loci, .loci, .person, .loci])
    #expect(positions == [.alone, .first, .middle, .last, .alone, .alone])
    #expect(positions.map { $0?.showsFace } == [true, false, false, true, true, true])
  }

  @Test func anEventBetweenBubblesStartsANewRun() {
    #expect(BubbleLayout.positions([.loci, .loci, nil, .loci]) == [.first, .last, nil, .alone])
  }

  @Test func aWiderGapOpensOnlyWhereTheSpeakerChanges() {
    #expect(
      BubbleLayout.turns([.person, .loci, .loci, nil, .loci, .person]) == [false, true, false, false, false, true])
  }
}
