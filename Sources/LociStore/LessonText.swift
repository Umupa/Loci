import Foundation
import LociModel

/// A lesson file: YAML front matter listing its sources, then the Markdown body.
///
/// ```
/// ---
/// sources:
/// - 019a8f40-1b2c-7d3e-8f40-5a6b7c8d9e0f
/// ---
/// # Body
/// ```
///
/// A file without front matter has no sources.
public struct LessonText: Hashable, Sendable {
  public let front: Lesson.Front
  public let body: String

  public init(front: Lesson.Front, body: String) {
    self.front = front
    self.body = body
  }

  public init(parsing text: String) throws {
    let parts = try Self.split(text)
    front = try parts.front.map { try Formats.fromYAML(Lesson.Front.self, $0) } ?? Lesson.Front(sources: [])
    body = parts.body
  }

  /// The body of a lesson file, even when its front matter is invalid.
  static func body(of text: String) -> String {
    (try? split(text).body) ?? text
  }

  public func text() throws -> String {
    "---\n\(try Formats.yaml(front))---\n\(body)"
  }

  private static let fence = "---"

  private static func split(_ text: String) throws -> (front: String?, body: String) {
    let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
    var lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)[...]
    guard lines.first == Substring(fence) else { return (nil, normalized) }
    lines = lines.dropFirst()
    guard let end = lines.firstIndex(of: Substring(fence)) else {
      throw UnclosedFrontMatter()
    }
    let front = lines[..<end].map { "\($0)\n" }.joined()
    return (front, lines[(end + 1)...].joined(separator: "\n"))
  }
}

extension LessonText {
  /// What a lesson cites, and the `loci://` links in its body that do not parse.
  public struct Citations: Hashable, Sendable {
    public let citations: [Citation]
    public let brokenLocators: [String]
  }

  /// The items listed in the front matter, then every place in the body a `loci://` link points into,
  /// in order and without repeats. Links inside fenced code blocks are examples, not citations.
  public func citations(in ref: LessonRef) -> Citations {
    Self.citations(in: ref, front: front, body: body)
  }

  static func citations(in ref: LessonRef, front: Lesson.Front?, body: String) -> Citations {
    var citations = front?.citations(in: ref) ?? []
    var broken: [String] = []
    for link in Self.links(in: body) {
      if let locator = Locator(link) {
        if let citation = Citation(in: ref, pointingAt: locator) { citations.append(citation) }
      } else {
        broken.append(link)
      }
    }
    var seen = Set<Citation>()
    return Citations(citations: citations.filter { seen.insert($0).inserted }, brokenLocators: broken)
  }

  private static func links(in body: String) -> [String] {
    var insideFence = false
    var links: [String] = []
    for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
      let trimmed = line.drop { $0 == " " }
      if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
        insideFence.toggle()
      } else if !insideFence {
        links += Self.links(onLine: line)
      }
    }
    return links
  }

  private static let scheme = "loci://"
  private static let linkEnds: Set<Character> = [")", "]", ">", "\"", "'", "<"]

  /// A plain scan rather than a regular expression: lessons are long and this runs on every rebuild.
  private static func links(onLine line: Substring) -> [String] {
    var links: [String] = []
    var rest = line
    while let start = rest.range(of: scheme) {
      var end = start.upperBound
      while end < rest.endIndex, !rest[end].isWhitespace, !linkEnds.contains(rest[end]) {
        end = rest.index(after: end)
      }
      links.append(String(rest[start.lowerBound..<end]))
      rest = rest[end...]
    }
    return links
  }
}

struct UnclosedFrontMatter: Error, CustomStringConvertible {
  var description: String { "the front matter has no closing ---" }
}
