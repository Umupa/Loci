/// What Loci wrote about one day, `diary/<day>.md`. It is for Loci itself; the person may read it.
///
/// ```md
/// # 2026-11-17 23:48 — 你读到了一点十分
///
/// The entry, in paragraphs.
///
/// ## To remember
/// - one thing
/// ```
public struct Diary: Hashable, Codable, Sendable {
  public let heading: Heading
  /// Markdown.
  public let body: String
  /// The list under `## To remember` at the end.
  public let toRemember: [String]

  public init(heading: Heading, body: String, toRemember: [String]) {
    self.heading = heading
    self.body = body
    self.toRemember = toRemember
  }

  public struct Heading: Hashable, Codable, Sendable {
    public let day: Day
    public let writtenAt: TimeOfDay?
    public let title: String?

    public init(day: Day, writtenAt: TimeOfDay?, title: String?) {
      self.day = day
      self.writtenAt = writtenAt
      self.title = title
    }
  }

  static let rememberHeadings: Set<String> = ["to remember", "要记住的"]

  /// Reads the file of `day`. Every part of the first line may be missing, and the day in the file
  /// name wins over one written there.
  public init(day: Day, parsing text: String) {
    var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    while let first = lines.first, first.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeFirst() }
    var writtenAt: TimeOfDay?
    var title: String?
    if let first = lines.first,
      let match = first.wholeMatch(of: /#\s+(?:\d{4}-\d\d-\d\d)?\s*(\d{1,2}:\d\d)?\s*(?:[—–-]+\s*)?(.*)/)
    {
      writtenAt = match.1.flatMap { TimeOfDay(String($0)) }
      let words = match.2.trimmingCharacters(in: .whitespaces)
      title = words.isEmpty ? nil : words
      lines.removeFirst()
    }
    let remember = lines.firstIndex { line in
      guard let match = line.wholeMatch(of: /#{2,3}\s+(.+)/) else { return false }
      return Self.rememberHeadings.contains(match.1.trimmingCharacters(in: .whitespaces).lowercased())
    }
    let body = lines[..<(remember ?? lines.endIndex)].joined(separator: "\n")
    let list = remember.map { lines[lines.index(after: $0)...].joined(separator: "\n") } ?? ""
    heading = Heading(day: day, writtenAt: writtenAt, title: title)
    self.body = body.trimmingCharacters(in: .whitespacesAndNewlines)
    toRemember = Bullets.pieces(of: list).map { piece in
      switch piece {
      case .item(_, let text): text
      case .other(let line): line.trimmingCharacters(in: .whitespaces)
      }
    }
  }
}
