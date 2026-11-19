import Foundation

/// A text file the rules read as words rather than as Swift: documentation, prompts, the changelog.
struct Prose {
  let path: String
  let lines: [String]

  init(path: String, text: String) {
    self.path = path
    self.lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
  }

  /// The lines under a `## ` heading, up to the next one.
  func section(_ heading: String) -> [(number: Int, text: String)] {
    let numbered = lines.enumerated().map { (number: $0.offset + 1, text: $0.element) }
    guard let start = numbered.firstIndex(where: { $0.text == "## \(heading)" }) else { return [] }
    let rest = numbered[(start + 1)...]
    return Array(rest.prefix { !$0.text.hasPrefix("## ") })
  }

  /// The cells of each body row of every Markdown table in some lines, header and rule rows left out.
  static func rows(of lines: [(number: Int, text: String)]) -> [(number: Int, cells: [String])] {
    var rows: [(number: Int, cells: [String])] = []
    var headerSeen = false
    for line in lines {
      guard line.text.hasPrefix("|") else {
        headerSeen = false
        continue
      }
      let cells = line.text.split(separator: "|", omittingEmptySubsequences: false).dropFirst().dropLast()
        .map { $0.trimmingCharacters(in: .whitespaces) }
      if cells.allSatisfy({ $0.allSatisfy { "-: ".contains($0) } }) {
        headerSeen = true
      } else if headerSeen {
        rows.append((line.number, cells))
      }
    }
    return rows
  }

  /// What sits between backticks in a line.
  static func code(in text: String) -> [String] {
    text.matches(of: /`([^`]+)`/).map { String($0.1) }
  }
}

enum Documents {
  static let glossary = "docs/features.md"
  static let changelog = "CHANGELOG.md"
  static let glossaryHeading = "词汇"
  static let retiredHeading = "不再用的词"

  /// Files that keep an old word on purpose, and why. Everything else uses the current vocabulary.
  static let keepsOldWords: [String: String] = [
    "Sources/LociStore/Schema.swift": "migrations already run on users' databases and are never edited"
  ]

  /// Everything a person or an agent reads to learn what Loci is now. The changelog counts up to its
  /// first released version; what was released stays as it was written.
  static func current() throws -> [Prose] {
    let notes = ["README.md", "AGENTS.md"].map { try? read($0) }.compactMap { $0 }
    let changelog = try read(changelog)
    let unreleased = Prose(
      path: changelog.path,
      text: changelog.lines.prefix { !isRelease($0) }.joined(separator: "\n"))
    return try notes + [unreleased] + files(in: "docs", extensions: ["md"])
      + files(in: "Sources", extensions: ["swift", "md", "xcstrings"])
  }

  /// Documentation whose links and paths must lead somewhere.
  static func linked() throws -> [Prose] {
    try ["README.md", "AGENTS.md", changelog].map(read) + files(in: "docs", extensions: ["md"])
  }

  static func isRelease(_ line: String) -> Bool {
    line.hasPrefix("## ") && line != "## Unreleased"
  }

  static func read(_ path: String) throws -> Prose {
    Prose(path: path, text: try String(contentsOf: Repository.root.appending(path: path), encoding: .utf8))
  }

  static func files(in folder: String, extensions: Set<String>) throws -> [Prose] {
    let base = Repository.root.appending(path: folder)
    guard let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else { return [] }
    return try walker.compactMap { $0 as? URL }
      .filter { extensions.contains($0.pathExtension) }
      .sorted { $0.path < $1.path }
      .map { try read(String($0.path.dropFirst(Repository.root.path.count + 1))) }
  }

  static func exists(_ path: String) -> Bool {
    FileManager.default.fileExists(atPath: Repository.root.appending(path: path).path)
  }
}
