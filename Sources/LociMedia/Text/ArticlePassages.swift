import Foundation
import Markdown

/// The passages of an article that are translated: each heading and each paragraph, also inside lists and
/// quotes, as the Markdown the parser writes back for it. Code, tables, raw HTML, pictures standing alone and
/// display formulas stay as they are. The reader finds a passage's translation by the same Markdown.
public enum ArticlePassages {
  /// In reading order, each once. `title` heads the article when its text does not start with a title of its own,
  /// as the reader shows it.
  public static func of(_ markdown: String, title: String? = nil) -> [String] {
    var passages: [String] = []
    var seen: Set<String> = []
    func visit(_ markup: any Markup) {
      switch markup {
      case let heading as Heading:
        add(heading)
      case let paragraph as Paragraph:
        if isTranslatable(paragraph) { add(paragraph) }
      case is CodeBlock, is HTMLBlock, is Table, is ThematicBreak:
        break
      default:
        for child in markup.children { visit(child) }
      }
    }
    func add(_ markup: any Markup) {
      let source = source(of: markup)
      guard !source.isEmpty, seen.insert(source).inserted else { return }
      passages.append(source)
    }
    for child in Document(parsing: titled(markdown, title)).children { visit(child) }
    return passages
  }

  /// The article as the reader shows it: with `title` as its first heading unless it starts with one.
  public static func titled(_ markdown: String, _ title: String?) -> String {
    guard let title, !markdown.hasPrefix("# ") else { return markdown }
    return "# \(title)\n\n" + markdown
  }

  /// The Markdown a heading or paragraph is known by.
  public static func source(of markup: any Markup) -> String {
    markup.detachedFromParent.format().trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// A picture on its own, or a display formula, has nothing to translate.
  public static func isTranslatable(_ paragraph: Paragraph) -> Bool {
    if paragraph.childCount == 1, paragraph.child(at: 0) is Markdown.Image { return false }
    let plain = paragraph.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
    if plain.count > 4, plain.hasPrefix("$$"), plain.hasSuffix("$$") { return false }
    return plain.contains { $0.isLetter }
  }
}
