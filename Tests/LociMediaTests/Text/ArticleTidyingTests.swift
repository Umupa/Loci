import LociMedia
import Testing

/// What a tidied article must keep before it replaces the original (TD-S3), and how it is cut up (TD-S2).
struct ArticleTidyingTests {
  static let article = """
    2026年11月18日

    [工程](https://openai.com/news/engineering/)

    We built the [sandbox ⁠（在新窗口中打开）](https://example.com/sandbox) so commands stay inside it.

    #### Python

    ```
    def spawn(): pass
    ```

    ![A flow chart](images/flow.webp)

    ## 继续阅读[How performance stays fast](https://openai.com/fast/)
    """

  static let tidied = """
    We built the [sandbox](https://example.com/sandbox) so commands stay inside it.

    ```python
    def spawn(): pass
    ```

    ![A flow chart](images/flow.webp)
    """

  @Test func piecesJoinBackIntoTheWholeArticle() {
    let markdown = (1...40).map { "## Part \($0)\n\n" + String(repeating: "Words about part \($0). ", count: 12) }
      .joined(separator: "\n\n")
    let pieces = ArticleTidying.pieces(of: markdown, size: 2000)

    #expect(pieces.count > 1)
    #expect(pieces.joined(separator: "\n") == markdown)
    #expect(pieces.allSatisfy { $0.hasPrefix("## Part") })
  }

  @Test func aShortArticleIsOnePiece() {
    #expect(ArticleTidying.pieces(of: Self.article) == [Self.article])
  }

  @Test func aTidyingThatKeepsPicturesCodeAndLinksMayReplaceTheArticle() {
    #expect(ArticleTidying.problem(tidying: Self.article, into: Self.tidied) == nil)
  }

  @Test func aTidyingThatLosesAPictureIsRefused() {
    let lost = Self.tidied.replacing("![A flow chart](images/flow.webp)", with: "A flow chart")
    #expect(ArticleTidying.problem(tidying: Self.article, into: lost) == .pictures)
  }

  @Test func aTidyingThatChangesCodeIsRefused() {
    let changed = Self.tidied.replacing("def spawn(): pass", with: "def spawn():\n    pass")
    #expect(ArticleTidying.problem(tidying: Self.article, into: changed) == .code)
  }

  @Test func aBlockOfLineNumbersMayGo() {
    let numbered = Self.article.replacing("#### Python", with: "```\n1\n2\n3\n```")
    #expect(ArticleTidying.problem(tidying: numbered, into: Self.tidied) == nil)
  }

  @Test func aTidyingThatMakesUpALinkIsRefused() {
    let invented = Self.tidied + "\n\nSee [the docs](https://example.com/docs)."
    #expect(ArticleTidying.problem(tidying: Self.article, into: invented) == .links)
  }

  @Test func aTidyingThatDropsMostOfALongArticleIsRefused() {
    let long = (1...30).map { "Paragraph \($0) says something worth keeping." }.joined(separator: "\n\n")
    let cut = (1...10).map { "Paragraph \($0) says something worth keeping." }.joined(separator: "\n\n")
    #expect(ArticleTidying.problem(tidying: long, into: cut) == .shorter)
    #expect(ArticleTidying.problem(tidying: long, into: long + "\n\n" + long) == .longer)
    #expect(ArticleTidying.problem(tidying: long, into: "") == .empty)
  }

  @Test func passagesFindTheirTidiedSelves() {
    let old = [
      "We built the [sandbox ⁠（在新窗口中打开）](https://example.com/sandbox) so commands stay inside it.",
      "Plain words stay the same.",
      "**Bold** words became plain.",
      "A passage the tidying removed.",
    ]
    let tidied = [
      "We built the [sandbox](https://example.com/sandbox) so commands stay inside it.",
      "Plain words stay the same.",
      "Bold words became plain.",
    ]
    #expect(
      ArticleTidying.passages(old, in: tidied) == [
        "We built the [sandbox](https://example.com/sandbox) so commands stay inside it.",
        "Plain words stay the same.", "Bold words became plain.", nil,
      ])
  }
}
