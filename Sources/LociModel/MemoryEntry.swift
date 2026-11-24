/// One thing remembered in `MEMORY.md` or `USER.md`: `- [day] text [loci:// link]`.
public struct MemoryEntry: Hashable, Codable, Sendable {
  /// The day it was said or learned; `nil` when the line has none.
  public let day: Day?
  /// The words, without the day and without the link to the source.
  public let text: String
  public let source: Source?
  /// The entry's first line as written, which `Forget` matches.
  public let line: String
  /// The wiki page that holds the detail, linked as `[title](memory/<page>.md)`; `nil` when it links none.
  public let page: WikiLink?

  public init(day: Day?, text: String, source: Source?, line: String, page: WikiLink? = nil) {
    self.day = day
    self.text = text
    self.source = source
    self.line = line
    self.page = page
  }

  /// Where it happened.
  public struct Source: Hashable, Codable, Sendable {
    public let locator: Locator
    /// `nil` when the item is no longer in the library.
    public let itemTitle: String?

    public init(locator: Locator, itemTitle: String?) {
      self.locator = locator
      self.itemTitle = itemTitle
    }
  }

  /// Reads a whole file. `title` names an item in the library, or gives `nil` for one that is gone.
  public static func lines(of text: String, title: (EntityID) -> String?) -> [Line<MemoryEntry>] {
    Bullets.pieces(of: text).map { piece in
      switch piece {
      case .other(let line):
        return .text(line)
      case .item(let line, let text):
        let (day, rest) = Bullets.leadingDay(text)
        let (linked, page) = WikiLink.take(from: rest)
        let (words, locator) = SourceLink.take(from: linked)
        guard !words.isEmpty || locator != nil else { return .text(line) }
        let source = locator.map { locator in
          Source(locator: locator, itemTitle: locator.item.flatMap(title))
        }
        return .entry(MemoryEntry(day: day, text: words, source: source, line: line, page: page))
      }
    }
  }

  /// The file without the entry whose first line is `line`, nor the lines continuing it; `nil` when no
  /// entry starts with that line.
  public static func removing(_ line: String, from text: String) -> String? {
    var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    guard let start = lines.firstIndex(where: { $0 == line }) else { return nil }
    var end = lines.index(after: start)
    while end < lines.endIndex, let first = lines[end].first, first == " " || first == "\t",
      !lines[end].trimmingCharacters(in: .whitespaces).isEmpty
    {
      end += 1
    }
    lines.removeSubrange(start..<end)
    return lines.joined(separator: "\n")
  }
}

extension Locator {
  /// The item this locator points into, if it points into the library.
  public var item: EntityID? {
    switch self {
    case .item(let item, _): item
    case .lesson: nil
    }
  }
}

/// The first `loci://` link in a line, written bare or as `[words](loci://…)`.
enum SourceLink {
  /// The line without the link, and the link. A Markdown link leaves its words; a link that does not
  /// parse stays in the line.
  static func take(from text: String) -> (String, Locator?) {
    if let match = text.firstMatch(of: /\[([^\]]*)\]\((loci:\/\/[^)\s]+)\)/), let locator = Locator(String(match.2)) {
      return (tidy(text.replacingCharacters(in: match.range, with: match.1)), locator)
    }
    guard let match = text.firstMatch(of: /loci:\/\/\S+/) else { return (text, nil) }
    var token = String(match.output)
    while !token.isEmpty {
      if let locator = Locator(token) {
        let end = text.index(match.range.lowerBound, offsetBy: token.count)
        return (tidy(text.replacingCharacters(in: match.range.lowerBound..<end, with: "")), locator)
      }
      token.removeLast()
    }
    return (text, nil)
  }

  private static func tidy(_ text: String) -> String {
    text.replacing(/[ \t]{2,}/, with: " ").trimmingCharacters(in: .whitespaces)
  }
}
