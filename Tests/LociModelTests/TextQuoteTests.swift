import Testing

@testable import LociModel

struct TextQuoteTests {
  static let text = "调度器先过滤节点。然后打分。过滤之后，调度器再次过滤节点。"

  @Test func aQuoteFindsItsWords() throws {
    let quote = try TextQuote("然后打分")
    let range = try #require(quote.range(in: Self.text))

    #expect(Self.text[range] == "然后打分")
  }

  @Test func theContextPicksBetweenTheSameWordsInTwoPlaces() throws {
    let second = try #require(Self.text.range(of: "过滤节点", options: .backwards))
    let quote = try TextQuote(quoting: second, in: Self.text)

    #expect(quote.range(in: Self.text) == second)
  }

  @Test func aQuoteStillFindsItsWordsAfterTheTextAroundThemIsRevised() throws {
    let quote = try TextQuote("然后打分", before: "节点。", after: "。过滤")
    let revised = "调度器先排除不合适的节点，然后打分，最后绑定。"
    let range = try #require(quote.range(in: revised))

    #expect(revised[range] == "然后打分")
  }

  @Test func aQuoteWhoseWordsAreGoneFindsNothing() throws {
    let quote = try TextQuote("抢占")

    #expect(quote.range(in: Self.text) == nil)
  }

  @Test func quotingKeepsOnlyAShortContextAndNoneAtTheEdges() throws {
    let text = String(repeating: "长", count: 100) + "要点" + String(repeating: "尾", count: 100)
    let middle = try #require(text.range(of: "要点"))
    let quote = try TextQuote(quoting: middle, in: text)

    #expect(quote.before == String(repeating: "长", count: TextQuote.contextLength))
    #expect(quote.after == String(repeating: "尾", count: TextQuote.contextLength))
    #expect(try TextQuote(quoting: text.startIndex..<middle.lowerBound, in: text).before == nil)
  }

  @Test func quotingOnlyWhitespaceIsRefused() throws {
    let text = "前文   后文"
    let spaces = try #require(text.range(of: "   "))
    #expect(throws: ModelError.self) { try TextQuote(quoting: spaces, in: text) }
  }
}
