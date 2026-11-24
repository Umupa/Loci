import Foundation

/// A link to a page of the companion's wiki, `memory/<name>.md`, written `[title](memory/<name>.md)` in the
/// index and `[title](<name>.md)` from one page to another.
public struct WikiLink: Hashable, Codable, Sendable {
  /// The page's file name without `.md`: short lowercase English.
  public let name: String
  /// The words the link is written with.
  public let title: String

  public init(name: String, title: String) {
    self.name = name
    self.title = title
  }

  /// `memory/<name>.md`, relative to `agent/`.
  public var path: String { "memory/\(name).md" }

  /// Whether `name` can name a page: lowercase letters, digits and hyphens, starting with a letter or digit.
  public static func isName(_ name: String) -> Bool {
    name.wholeMatch(of: /[a-z0-9][a-z0-9-]{0,63}/) != nil
  }

  /// The line without its first link to a page, the link's words left in place of it, and the link.
  static func take(from text: String) -> (String, WikiLink?) {
    guard let match = text.firstMatch(of: /\[([^\]]+)\]\((?:memory\/)?([a-z0-9][a-z0-9-]*)\.md\)/) else {
      return (text, nil)
    }
    let link = WikiLink(name: String(match.2), title: String(match.1))
    let rest = text.replacingCharacters(in: match.range, with: "").replacing(/[ \t]{2,}/, with: " ")
    return (rest.trimmingCharacters(in: .whitespaces), link)
  }

  /// Every link to a page in a text, in order, repeats kept.
  public static func all(in text: String) -> [WikiLink] {
    text.matches(of: /\[([^\]]+)\]\((?:memory\/)?([a-z0-9][a-z0-9-]*)\.md\)/).map {
      WikiLink(name: String($0.2), title: String($0.1))
    }
  }
}

/// Where words were said, as `loci recall` finds them: the conversation or run record, and the words around
/// the match.
public struct RecallHit: Hashable, Codable, Sendable {
  /// `conversations/<day>/<file>.md` or `runs/<day>/<id>.md`, relative to `agent/`.
  public let path: String
  public let day: Day?
  public let snippet: String

  public init(path: String, day: Day?, snippet: String) {
    self.path = path
    self.day = day
    self.snippet = snippet
  }
}

/// Searches every conversation and every run record for words, as the companion recalls what was said.
public struct Recall: LocalToolCommand {
  public static let name = "loci.recall"
  public let text: String
  public let limit: Int

  public init(_ text: String, limit: Int = 20) {
    self.text = text
    self.limit = limit
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> [RecallHit] {
    try await handler.recall(self)
  }
}

/// A page of the wiki as the memory page shows it: its title and its lines.
public struct WikiPage: Hashable, Codable, Sendable {
  public let name: String
  /// The page's `# ` heading; the name when it has none.
  public let title: String
  public let lines: [Line<MemoryEntry>]

  public init(name: String, title: String, lines: [Line<MemoryEntry>]) {
    self.name = name
    self.title = title
    self.lines = lines
  }

  /// Reads a page's text. `title` names an item in the library, or gives `nil` for one that is gone.
  public init(name: String, parsing text: String, title itemTitle: (EntityID) -> String?) {
    let heading = text.split(separator: "\n").first { $0.hasPrefix("# ") }
    self.name = name
    title = heading.map { String($0.dropFirst(2)).trimmingCharacters(in: .whitespaces) } ?? name
    lines = MemoryEntry.lines(of: text, title: itemTitle).filter { line in
      if case .text(let words) = line { return !words.hasPrefix("# ") && !words.isEmpty }
      return true
    }
  }
}

/// A page of the wiki, kept current as the daily review and the person change it.
public struct WatchWikiPage: Subscription {
  public static let name = "loci.wikiPage"
  public let page: String

  public init(_ page: String) {
    self.page = page
  }

  public func value(from handler: any CommandHandler) async throws(HostError) -> WikiPage {
    try await handler.wikiPage(page)
  }

  /// Items name the sources of its lines.
  public func isAffected(by changes: Set<ContentChange>) -> Bool {
    changes.contains(.loci(.wiki)) || changes.contains(.everything)
      || changes.contains { if case .item = $0 { true } else { false } }
  }
}

/// Removes one entry, and the lines continuing it, from a page of the wiki. `notFound` when no entry starts
/// with that line any more.
public struct ForgetWikiLine: RemoteCommand {
  public static let name = "loci.forgetWikiLine"
  public let page: String
  /// `MemoryEntry.line`.
  public let line: String

  public init(_ line: String, on page: String) {
    self.page = page
    self.line = line
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.forgetWikiLine(self)
  }
}
