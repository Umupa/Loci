import Foundation
import LociModel

/// What Loci is doing while it answers, said the way a person would: never a command, a path or a count.
enum Doing: Hashable {
  case thinking
  /// Searching the web for these words.
  case searching(String)
  /// Reading a page on this site.
  case site(String)
  /// Looking at a repository's pull requests, or issues; `nil` when it is not named.
  case pullRequests(String?)
  case issues(String?)
  /// Looking at what changed in a repository.
  case history
  case library
  case saving
  /// Reading a document, by its title when its name says one.
  case reading(String?)
  case lookingThrough
  case writing
  case tidying
  case trying

  /// What the last thought or tool among `messages` was about; thinking until there is one.
  init(_ messages: [Message]) {
    let last = messages.last { message in
      switch message.body {
      case .thinking, .tool: true
      default: false
      }
    }
    guard case .tool(let tool) = last?.body else {
      self = .thinking
      return
    }
    self.init(tool)
  }

  init(_ tool: ToolActivity) {
    let subject = tool.subject.flatMap { $0.isEmpty ? nil : $0 }
    if let site = subject.flatMap(Self.site) {
      self = .site(site)
      return
    }
    switch tool.kind {
    case .execute:
      self = subject.map { Self.command(Self.unwrapped($0)) } ?? .trying
    case .search where Self.isWebSearch(tool.name):
      self = subject.map { .searching(Self.short(Self.sitesOnly($0))) } ?? .thinking
    case .search:
      self = .lookingThrough
    case .read:
      self = .reading(subject.flatMap(Self.title))
    case .edit, .create:
      self = .writing
    case .delete:
      self = .tidying
    case .other:
      self = .trying
    }
  }

  var words: LocalizedStringResource {
    switch self {
    case .thinking: .loci("doing.thinking")
    case .searching(let words): .loci("doing.searching \(words)")
    case .site(let site): .loci("doing.site \(site)")
    case .pullRequests(let repository?): .loci("doing.pullRequests \(repository)")
    case .pullRequests(nil): .loci("doing.anyPullRequests")
    case .issues(let repository?): .loci("doing.issues \(repository)")
    case .issues(nil): .loci("doing.anyIssues")
    case .history: .loci("doing.history")
    case .library: .loci("doing.library")
    case .saving: .loci("doing.saving")
    case .reading(let title?): .loci("doing.reading \(title)")
    case .reading(nil): .loci("doing.readingAnything")
    case .lookingThrough: .loci("doing.lookingThrough")
    case .writing: .loci("doing.writing")
    case .tidying: .loci("doing.tidying")
    case .trying: .loci("doing.trying")
    }
  }

  private static func command(_ line: String) -> Doing {
    let words = line.split(whereSeparator: \.isWhitespace).map(String.init)
    let program = words.first.map { URL(filePath: $0).lastPathComponent }
    if program == "curl" || program == "wget", let site = words.lazy.compactMap(site).first {
      return .site(site)
    }
    switch (program, words.dropFirst().first) {
    case ("gh", "pr"): return .pullRequests(repository(in: words))
    case ("gh", "issue"): return .issues(repository(in: words))
    case ("git", "log"), ("git", "show"), ("git", "diff"), ("git", "blame"): return .history
    case ("loci", "save"), ("loci", "import"), ("loci", "add"): return .saving
    case ("loci", _): return .library
    case ("rg", _), ("grep", _), ("find", _), ("fd", _), ("ls", _): return .lookingThrough
    default: return .trying
    }
  }

  /// The repository a `gh` command names with `-R` or `--repo`, without its owner.
  private static func repository(in words: [String]) -> String? {
    guard let flag = words.firstIndex(where: { $0 == "-R" || $0 == "--repo" }), flag + 1 < words.count else {
      return nil
    }
    return words[flag + 1].split(separator: "/").last.map(String.init)
  }

  /// How much of a search fits the line, a Chinese character counting twice.
  private static let roomForWords = 28

  /// The words cut at the last space that fits, or where the room ends, with an ellipsis.
  private static func short(_ words: String) -> String {
    var used = 0
    var end = words.startIndex
    for index in words.indices {
      used += words[index].isASCII ? 1 : 2
      if used > roomForWords { break }
      end = words.index(after: index)
    }
    guard end < words.endIndex else { return words }
    let kept = words[..<end]
    let cut = kept.lastIndex(of: " ").map { kept[..<$0] } ?? kept
    return cut.trimmingCharacters(in: .whitespaces) + "…"
  }

  /// Each web address in the words said as its site.
  private static func sitesOnly(_ words: String) -> String {
    words.split(separator: " ", omittingEmptySubsequences: false).map { site(String($0)) ?? String($0) }
      .joined(separator: " ")
  }

  /// The site of a web address, without `www.`.
  private static func site(_ text: String) -> String? {
    guard text.hasPrefix("http://") || text.hasPrefix("https://"), let host = URL(string: text)?.host() else {
      return nil
    }
    return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
  }

  private static let documents: Set<String> = ["md", "markdown", "txt", "pdf", "html", "htm", "rst", "org"]
  private static let unnamed: Set<String> = ["text", "index", "readme", "content", "item", "notes", "body"]

  /// A document's name said as words: `firecracker-design.md` is `firecracker design`. Code, and documents
  /// with a name that says nothing, have none.
  private static func title(_ path: String) -> String? {
    let file = URL(filePath: path)
    guard documents.contains(file.pathExtension.lowercased()) else { return nil }
    let stem = file.deletingPathExtension().lastPathComponent
    guard !unnamed.contains(stem.lowercased()), stem.contains(where: \.isLetter) else { return nil }
    return stem.replacing(/[-_]+/, with: " ")
  }

  /// The command a shell was asked to run, without the shell: `/bin/zsh -lc 'ls -a'` is `ls -a`.
  private static func unwrapped(_ command: String) -> String {
    let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let match = trimmed.firstMatch(of: /^(?:\S*\/)?(?:zsh|bash|sh)\s+-l?c\s+(?<body>[\s\S]+)$/) else {
      return trimmed
    }
    let body = String(match.body)
    guard body.count >= 2, let quote = body.first, quote == "'" || quote == "\"", body.last == quote else {
      return body
    }
    return String(body.dropFirst().dropLast())
  }

  private static func isWebSearch(_ name: String) -> Bool {
    let plain = name.lowercased().filter(\.isLetter)
    return plain == "websearch" || plain == "search" || plain == "googlesearch"
  }
}
