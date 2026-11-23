import AppKit
import Testing

@testable import LociUI

@MainActor
struct ReadingTextTests {
  static let lesson = """
    # 调度器

    调度分两步：**过滤**，然后 `打分`。

    ## 过滤

    - 资源够不够
    - 端口有没有冲突

    1. 预选
    2. 优选

    > 约束是硬的。

    ```go
    func filter() {
      return
    }
    ```

    | 阶段 | 回答 |
    |---|---|
    | 过滤 | 能不能 |
    | 打分 | 好不好 |

    ---

    见 [Borg](https://research.google/pubs/borg/)。
    """

  static func decoration(of line: String, in text: ReadingText) throws -> BlockDecoration? {
    let range = (text.plain as NSString).range(of: line)
    try #require(range.location != NSNotFound)
    let raw = text.string.attribute(BlockDecoration.key, at: range.location, effectiveRange: nil) as? String
    return raw.flatMap(BlockDecoration.init(rawValue:))
  }

  @Test func markdownBecomesTextWithoutItsMarkup() {
    let text = ReadingText(markdown: Self.lesson)

    #expect(text.plain.hasPrefix("调度器\n调度分两步：过滤，然后 打分。\n过滤\n"))
    #expect(!text.plain.contains("**"))
    #expect(!text.plain.contains("`"))
    #expect(!text.plain.contains("|"))
    #expect(text.plain.hasSuffix("见 Borg。"))
  }

  @Test func headingsAreListedWithWhereTheyStart() {
    let text = ReadingText(markdown: Self.lesson)

    #expect(text.headings.map(\.title) == ["调度器", "过滤"])
    #expect(text.headings.map(\.level) == [1, 2])
    #expect(text.headings.allSatisfy { (text.plain as NSString).substring(from: $0.offset).hasPrefix($0.title) })
  }

  @Test func listItemsStartWithTheirMarkers() {
    let plain = ReadingText(markdown: Self.lesson).plain

    #expect(plain.contains("•\t资源够不够\n•\t端口有没有冲突\n"))
    #expect(plain.contains("1.\t预选\n2.\t优选\n"))
  }

  @Test func aCodeBlockKeepsItsLinesAndIsDrawnAsOneBlock() throws {
    let text = ReadingText(markdown: Self.lesson)

    #expect(text.plain.contains("func filter() {\n  return\n}\n"))
    #expect(try Self.decoration(of: "func filter() {", in: text) == .codeFirst)
    #expect(try Self.decoration(of: "  return", in: text) == .codeMiddle)
    #expect(try Self.decoration(of: "}", in: text) == .codeLast)
    #expect(try Self.decoration(of: "调度分两步", in: text) == nil)
  }

  @Test func tableCellsKeepTheirOriginalWordsForQuotes() throws {
    let text = ReadingText(markdown: Self.lesson)
    let shown = (text.plain as NSString).range(of: "\u{FFFC}")
    try #require(shown.location != NSNotFound)
    #expect(text.string.attribute(.attachment, at: shown.location, effectiveRange: nil) is ReaderTableAttachment)
    #expect(text.original.contains("阶段\t回答\n过滤\t能不能\n打分\t好不好\n"))
    #expect(text.quote(shown)?.excerpt == "阶段\t回答\n过滤\t能不能\n打分\t好不好")
  }

  @Test func quotesAndLinksKeepWhatTheyAre() throws {
    let text = ReadingText(markdown: Self.lesson)
    let link = (text.plain as NSString).range(of: "Borg")

    #expect(try Self.decoration(of: "约束是硬的。", in: text) == .quote)
    #expect(
      text.string.attribute(.link, at: link.location, effectiveRange: nil) as? URL
        == URL(string: "https://research.google/pubs/borg/"))
  }

  @Test func theSameMarkdownAlwaysGivesTheSameText() {
    #expect(ReadingText(markdown: Self.lesson).plain == ReadingText(markdown: Self.lesson).plain)
  }

  @Test func codeWithALanguageIsColoredByWhatEachWordIs() {
    let text = ReadingText(markdown: "```go\nfunc filter() string {\n  return \"ok\"\n}\n```")
    let plain = text.plain as NSString
    func color(of word: String) -> NSColor? {
      text.string.attribute(.foregroundColor, at: plain.range(of: word).location, effectiveRange: nil) as? NSColor
    }

    #expect(color(of: "return") == Tones.codeKeyword)
    #expect(color(of: "filter") == Tones.codeName)
    #expect(color(of: "\"ok\"") == Tones.codeString)
  }

  @Test func codeWithoutALanguageStaysOneColor() {
    let text = ReadingText(markdown: "```\nfunc filter() {}\n```")

    #expect(text.string.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == Tones.ink)
  }

  @Test func formulasAreSetInPlaceOfTheirSource() {
    let block = ReadingText(markdown: "前文\n\n```math\n\\frac{a}{b}\n```\n\n$$x^2$$\n\n面积是 $\\pi r^2$。")

    #expect(block.plain == "前文\n\u{FFFC}\n\u{FFFC}\n面积是 \u{FFFC}。")
    #expect(block.string.attribute(.attachment, at: 3, effectiveRange: nil) is NSTextAttachment)
  }

  @Test func dollarsThatAreNotFormulasStayAsWritten() {
    #expect(ReadingText(markdown: "从 $5 涨到 $6。").plain == "从 $5 涨到 $6。")
    #expect(ReadingText(markdown: "```math\n\\frac{\n```").plain == "\\frac{")
  }
}
