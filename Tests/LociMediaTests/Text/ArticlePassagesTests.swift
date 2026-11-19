import LociMedia
import Testing

struct ArticlePassagesTests {
  @Test func headingsAndParagraphsAreTranslatedWithTheirInlineMarkdown() {
    let markdown = """
      # The Tail at Scale

      Systems that respond **quickly** feel more fluid. See [the paper](https://example.com).

      ## Why Variability Exists?

      - Shared resources
      - Daemons, and `cron`

      > Queueing makes it worse.
      """
    #expect(
      ArticlePassages.of(markdown) == [
        "# The Tail at Scale",
        "Systems that respond **quickly** feel more fluid. See [the paper](https://example.com).",
        "## Why Variability Exists?",
        "Shared resources",
        "Daemons, and `cron`",
        "Queueing makes it worse.",
      ])
  }

  @Test func codePicturesTablesAndFormulasStayAsTheyAre() {
    let markdown = """
      ```swift
      let x = 1
      ```

      ![A chart](images/chart.png)

      | a | b |
      |---|---|
      | 1 | 2 |

      $$
      p = 1 - 0.99^{100}
      $$

      ---

      <div>raw</div>

      42%
      """
    #expect(ArticlePassages.of(markdown).isEmpty)
  }

  @Test func aPassageThatRepeatsIsTranslatedOnce() {
    #expect(ArticlePassages.of("Read on.\n\nMore.\n\nRead on.") == ["Read on.", "More."])
  }
}
