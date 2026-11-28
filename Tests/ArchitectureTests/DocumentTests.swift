import Foundation
import Testing

/// The documents describe the app as it is now. These rules catch the drift a change leaves behind.
struct DocumentTests {
  @Test func retiredWordsAreGone() throws {
    let glossary = try Documents.read(Documents.glossary)
    let retired = try Self.retiredWords(in: glossary).map {
      (word: $0.word, instead: $0.instead, matches: try Self.matcher(for: $0.word))
    }
    let table = Set(glossary.section(Documents.retiredHeading).map(\.number))
    let roadmap = try Documents.read(Documents.roadmap)
    let history = Set(roadmap.section(Documents.releasedHeading).map(\.number))

    report(
      try Documents.current().filter { Documents.keepsOldWords[$0.path] == nil }.flatMap { file in
        file.lines.enumerated().flatMap { index, line -> [Violation] in
          if file.path == Documents.glossary && table.contains(index + 1) { return [] }
          if file.path == Documents.roadmap,
            history.contains(index + 1) || line.hasPrefix(Documents.retirementLine)
          {
            return []
          }
          return retired.filter { $0.matches(line) }.map {
            Violation(
              file: file.path, line: index + 1, found: "「\($0.word)」 is retired",
              fix: "Say \($0.instead). If the thing is gone, delete the sentence; git keeps the history. "
                + "A file that must keep the word, such as an applied migration, goes in Documents.keepsOldWords.")
          }
        }
      })
  }

  @Test func glossaryNamesAreTypesInTheCode() throws {
    let declared = Set(
      try Repository.files(in: "Sources").flatMap(\.lines).flatMap { line in
        line.code.matches(of: /\b(?:struct|enum|class|actor|protocol|typealias)\s+(\w+)/).map { String($0.1) }
      })
    let glossary = try Documents.read(Documents.glossary)

    report(
      Prose.rows(of: glossary.section(Documents.glossaryHeading)).flatMap { row in
        row.cells.dropFirst(2).flatMap(Prose.code).compactMap { name -> Violation? in
          let type = String(name.prefix { $0 != "." })
          guard type.first?.isUppercase == true, !declared.contains(type) else { return nil }
          return Violation(
            file: glossary.path, line: row.number, found: "`\(type)` is not declared in Sources",
            fix: "The word and the type are one name. Rename the type to match, or update the row; "
              + "if the thing is gone, delete the row and add the word to 「\(Documents.retiredHeading)」.")
        }
      })
  }

  @Test func linksAndPathsLeadToFiles() throws {
    report(
      try Documents.linked().flatMap { file in
        file.lines.enumerated().flatMap { index, line in
          Self.brokenReferences(in: line, of: file.path).map {
            Violation(
              file: file.path, line: index + 1, found: "\($0) does not exist",
              fix: "Point it at what the thing is called now, or delete the sentence if the thing is gone.")
          }
        }
      })
  }

  @Test func changelogIsVersioned() throws {
    let changelog = try Documents.read(Documents.changelog)
    let headings = changelog.lines.enumerated().filter { $0.element.hasPrefix("## ") }

    #expect(headings.first?.element == "## Unreleased", "CHANGELOG.md starts with `## Unreleased`")
    report(
      headings.dropFirst().filter { !$0.element.contains(/^## \d+\.\d+\.\d+(-[0-9A-Za-z.]+)? — \d{4}-\d{2}-\d{2}$/) }
        .map {
          Violation(
            file: changelog.path, line: $0.offset + 1, found: $0.element,
            fix: "A released section is `## 1.1.0 — 2026-11-20`: the tag without `v`, then the day.")
        })
  }

  static func retiredWords(in glossary: Prose) -> [(word: String, instead: String)] {
    Prose.rows(of: glossary.section(Documents.retiredHeading)).flatMap { row in
      row.cells[0].split(separator: "、").map {
        (String($0).trimmingCharacters(in: CharacterSet(charactersIn: "` ")), row.cells[1])
      }
    }
  }

  /// Latin words match at the start of a word in any case, so `mentor` finds `Mentors` and `mentor_id`.
  static func matcher(for word: String) throws -> (String) -> Bool {
    guard word.allSatisfy(\.isASCII) else { return { $0.contains(word) } }
    let pattern = try Regex("\\b" + NSRegularExpression.escapedPattern(for: word)).ignoresCase()
    return { $0.contains(pattern) }
  }

  static func brokenReferences(in line: String, of path: String) -> [String] {
    let folder = path.split(separator: "/").dropLast().map(String.init)
    let links = line.matches(of: /\]\(([^)\s]+)\)/).map { String($0.1) }
      .filter { !$0.contains("://") && !$0.hasPrefix("#") && !$0.hasPrefix("mailto:") }
      .map { String($0.prefix { $0 != "#" }) }
      .filter { !Documents.exists(Self.resolve($0, from: folder)) }
    let paths = Prose.code(in: line)
      .filter { $0.contains(/^(Sources|Tests|script|docs)\/[^\s<>*…{]+$/) }
      .map { String($0.prefix { $0 != ":" }) }
      .filter { !Documents.exists($0) }
    return links + paths
  }

  static func resolve(_ link: String, from folder: [String]) -> String {
    link.split(separator: "/").reduce(into: folder) { parts, part in
      switch part {
      case ".": break
      case "..": _ = parts.popLast()
      default: parts.append(String(part))
      }
    }.joined(separator: "/")
  }
}

/// The rules above read Markdown by hand; these keep that reading honest.
struct ProseReaderTests {
  @Test func readsTableRowsUnderAHeading() {
    let file = Prose(
      path: "x.md",
      text: """
        ## 不再用的词

        | 词 | 改用 |
        |---|---|
        | 旧词、`Old` | 新词 |

        ## 下一节
        | a | b |
        |---|---|
        | 不在这节 | x |
        """)

    let words = DocumentTests.retiredWords(in: file)

    #expect(words.map(\.word) == ["旧词", "Old"])
    #expect(words.map(\.instead) == ["新词", "新词"])
  }

  @Test func matchesLatinWordsByTheirStartAndChineseAnywhere() throws {
    let latin = try DocumentTests.matcher(for: "widget")
    let chinese = try DocumentTests.matcher(for: "旧词")
    #expect(latin("let widgets_id = 1"))
    #expect(latin("A Widget here"))
    #expect(!latin("subwidget"))
    #expect(chinese("这是旧词。"))
  }

  @Test func findsLinksAndPathsThatLeadNowhere() {
    let line =
      "See [arch](architecture.md), [gone](gone.md), `Package.swift`, `Sources/Nope.swift:3`, `docs/x/<名字>.md`."

    #expect(DocumentTests.brokenReferences(in: line, of: "docs/roadmap.md") == ["gone.md", "Sources/Nope.swift"])
  }
}
