import Foundation
import Markdown

/// Tidying an article: the text cut into pieces a model rewrites one at a time, and the checks a rewritten piece
/// must pass before it may take the original's place. Tidying leaves no copy of the original behind, so a piece
/// that loses a picture, changes code, makes up a link or drops much of the text is refused.
public enum ArticleTidying {
  /// Pieces of about `size` characters that join back, with line breaks, into `markdown`. A piece ends before a
  /// heading once it is half full, so sections stay together.
  public static func pieces(of markdown: String, size: Int = 6000) -> [String] {
    let lines = markdown.components(separatedBy: "\n")
    let starts = Document(parsing: markdown).children.compactMap { block -> (line: Int, heading: Bool)? in
      guard let line = block.range?.lowerBound.line, line > 1 else { return nil }
      return (line - 1, block is Heading)
    }
    func characters(_ range: Range<Int>) -> Int { lines[range].reduce(0) { $0 + $1.count + 1 } }
    var cuts: [Int] = []
    var length = characters(0..<(starts.first?.line ?? lines.count))
    for (index, start) in starts.enumerated() {
      let block = characters(start.line..<(index + 1 < starts.count ? starts[index + 1].line : lines.count))
      if length > 0, length + block > size || (start.heading && length * 2 >= size) {
        cuts.append(start.line)
        length = 0
      }
      length += block
    }
    return zip([0] + cuts, cuts + [lines.count]).map { lines[$0..<$1].joined(separator: "\n") }
  }

  /// Why `tidied` cannot replace `original`, or `nil` when it can.
  public static func problem(tidying original: String, into tidied: String) -> TidyProblem? {
    let before = Contents(original)
    let after = Contents(tidied)
    guard !after.text.isEmpty || before.text.isEmpty else { return .empty }
    guard after.pictures.sorted() == before.pictures.sorted() else { return .pictures }
    let code = before.code.filter { !isLineNumbers($0) }
    guard after.code.allSatisfy(before.code.contains), code.allSatisfy(after.code.contains) else { return .code }
    guard after.links.isSubset(of: before.links.union(before.pictures)) else { return .links }
    if before.text.count >= 500, after.text.count * 2 < before.text.count { return .shorter }
    if after.text.count > before.text.count * 13 / 10 + 100 { return .longer }
    return nil
  }

  /// For each passage as `ArticlePassages` cut it before tidying, the same passage after: the one with the same
  /// Markdown, else the same words, else the one whose words are most alike, three quarters alike at least; `nil`
  /// when none is.
  public static func passages(_ old: [String], in tidied: [String]) -> [String?] {
    let words = tidied.map(plain)
    return old.map { passage in
      if tidied.contains(passage) { return passage }
      let text = plain(passage)
      guard !text.isEmpty else { return nil }
      if let same = words.firstIndex(of: text) { return tidied[same] }
      let pairs = Self.pairs(text)
      let alike = words.indices.map { (index: $0, share: Self.alike(pairs, Self.pairs(words[$0]))) }
      return alike.max { $0.share < $1.share }.flatMap { $0.share >= 0.75 ? tidied[$0.index] : nil }
    }
  }

  private static func pairs(_ text: String) -> Set<String> {
    let characters = Array(text.lowercased().filter { !$0.isWhitespace && !$0.isPunctuation })
    return Set(zip(characters, characters.dropFirst()).map { String([$0, $1]) })
  }

  private static func alike(_ one: Set<String>, _ other: Set<String>) -> Double {
    let all = one.union(other).count
    return all == 0 ? 0 : Double(one.intersection(other).count) / Double(all)
  }

  private static func plain(_ markdown: String) -> String {
    Contents(markdown).text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
  }

  private static func isLineNumbers(_ code: String) -> Bool {
    code.allSatisfy { $0.isNumber || $0.isWhitespace }
  }
}

/// Why a tidied piece of an article cannot take the original's place.
public enum TidyProblem: String, Error, Hashable, Sendable {
  case empty, pictures, code, links, shorter, longer

  public var reason: String {
    switch self {
    case .empty: "the tidied text came back empty"
    case .pictures: "the tidied text does not keep every picture"
    case .code: "the tidied text changes a code block"
    case .links: "the tidied text links somewhere the article does not"
    case .shorter: "the tidied text leaves out too much of the article"
    case .longer: "the tidied text adds words the article does not have"
    }
  }
}

private struct Contents: MarkupWalker {
  var text = ""
  var pictures: [String] = []
  var code: [String] = []
  var links: Set<String> = []

  init(_ markdown: String) {
    visit(Document(parsing: markdown))
  }

  mutating func visitText(_ piece: Markdown.Text) {
    text += piece.string + " "
  }

  mutating func visitInlineCode(_ inlineCode: InlineCode) {
    text += inlineCode.code + " "
  }

  mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
    code.append(codeBlock.code.trimmingCharacters(in: .newlines))
  }

  mutating func visitImage(_ image: Markdown.Image) {
    if let source = image.source { pictures.append(source) }
    descendInto(image)
  }

  mutating func visitLink(_ link: Markdown.Link) {
    if let destination = link.destination { links.insert(destination) }
    descendInto(link)
  }

  mutating func visitHTMLBlock(_ html: HTMLBlock) {
    pictures += Self.sources(in: html.rawHTML)
  }

  mutating func visitInlineHTML(_ html: InlineHTML) {
    pictures += Self.sources(in: html.rawHTML)
  }

  private static func sources(in html: String) -> [String] {
    html.matches(of: /<img[^>]*?\ssrc="([^"]+)"/).map { String($0.output.1) }
  }
}
