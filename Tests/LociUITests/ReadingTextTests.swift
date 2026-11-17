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

  @Test func tableCellsLineUpOnTabStopsUnderARuledHeader() throws {
    let text = ReadingText(markdown: Self.lesson)
    let header = (text.plain as NSString).range(of: "阶段\t回答")
    let style = text.string.attribute(.paragraphStyle, at: header.location, effectiveRange: nil) as? NSParagraphStyle

    #expect(text.plain.contains("阶段\t回答\n过滤\t能不能\n打分\t好不好\n"))
    #expect(try Self.decoration(of: "阶段\t回答", in: text) == .tableHeader)
    #expect(style?.tabStops.count == 1)
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
}
