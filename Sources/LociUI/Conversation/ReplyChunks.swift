import Foundation

/// A reply cut into pieces that are each drawn on their own, so that while it streams only the last piece
/// is laid out again and the pieces before it keep the layout they have.
///
/// A piece starts at a heading, at a paragraph after a blank line, and around a display formula, which is
/// a piece of its own so that it can be centred on the whole reply. Lists, code, quotes and tables stay
/// whole, and so does a list together with the paragraphs inside it. A reply with link references stays
/// one piece, because the references are only found in the piece that defines them.
struct ReplyChunks: Equatable {
  struct Chunk: Equatable {
    let markdown: String
    /// What the piece begins with, which decides how much room is left above it.
    let opening: Opening
    /// The piece is a display formula and nothing else.
    let isFormula: Bool
  }

  enum Opening: Equatable {
    case heading, code, other
  }

  let chunks: [Chunk]

  init(_ markdown: String) {
    let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)
    guard !lines.contains(where: Self.isReference) else {
      chunks = [Self.chunk(lines)]
      return
    }
    var chunks: [Chunk] = []
    var current: [Substring] = []
    var fence: Fence?
    var previous: Substring?
    var afterFormula = false
    for (index, line) in lines.enumerated() {
      let blank = line.allSatisfy(\.isWhitespace)
      if let open = fence {
        if open.closes(line) {
          fence = nil
          afterFormula = open.isFormula
        }
      } else if !blank {
        let next = lines.indices.contains(index + 1) ? lines[index + 1] : nil
        let blankBefore = current.last?.allSatisfy(\.isWhitespace) == true
        if let previous, current.contains(where: { !$0.allSatisfy(\.isWhitespace) }),
          Self.opens(line, after: previous, blankBefore: blankBefore, next: next)
            || (afterFormula && Self.follows(line))
        {
          chunks.append(Self.chunk(current))
          current = []
        }
        afterFormula = false
        fence = Fence(line)
      }
      current.append(line)
      if !blank { previous = line }
    }
    if !current.isEmpty { chunks.append(Self.chunk(current)) }
    self.chunks = chunks
  }

  private static func chunk(_ lines: [Substring]) -> Chunk {
    let filled = lines.filter { !$0.allSatisfy(\.isWhitespace) }
    let opener = filled.first.flatMap(Fence.init)
    let opening: Opening =
      filled.first.map(isHeading) == true ? .heading : opener.map { $0.isFormula ? .other : .code } ?? .other
    let isFormula =
      opener?.isFormula == true && filled.count >= 2 && opener?.closes(filled[filled.count - 1]) == true
      && !filled.dropFirst().dropLast().contains { opener?.closes($0) == true }
    return Chunk(markdown: lines.joined(separator: "\n"), opening: opening, isFormula: isFormula)
  }

  /// Whether a new piece can start at `line`: it begins a heading, a display formula, or a paragraph after a
  /// blank line, and what ends the piece before it, `previous`, leaves no room of its own below.
  private static func opens(_ line: Substring, after previous: Substring, blankBefore: Bool, next: Substring?)
    -> Bool
  {
    guard !previous.contains("|"), !isRule(previous), !isHeading(previous) else { return false }
    if isHeading(line) || Fence(line)?.isFormula == true { return true }
    guard blankBefore, let first = line.first, !first.isWhitespace, !line.contains("|") else { return false }
    if let next, isUnderline(next) || isDelimiter(next) { return false }
    return !(isListItem(line) || isRule(line) || ">$<".contains(first) || Fence(line) != nil)
  }

  /// Whether what comes after a display formula can start a piece of its own: anything but a table or a
  /// rule, which leave more room above them than a paragraph does.
  private static func follows(_ line: Substring) -> Bool {
    guard let first = line.first, !first.isWhitespace else { return false }
    return !(line.contains("|") || isRule(line))
  }

  private static func isHeading(_ line: Substring) -> Bool {
    let marks = line.prefix { $0 == "#" }.count
    return (1...6).contains(marks) && line.dropFirst(marks).first.map(\.isWhitespace) != false
  }

  private static func isListItem(_ line: Substring) -> Bool {
    let digits = line.prefix { $0.isASCII && $0.isNumber }.count
    let marker = digits > 0 ? line.dropFirst(digits).prefix(1) : line.prefix(1)
    guard digits > 0 ? (digits <= 9 && (marker == "." || marker == ")")) : "-*+".contains(marker) && !marker.isEmpty
    else { return false }
    return line.dropFirst(digits + 1).first.map(\.isWhitespace) != false
  }

  /// `---`, `***` or `___`, spaces allowed between.
  private static func isRule(_ line: Substring) -> Bool {
    let marks = line.filter { !$0.isWhitespace }
    guard let mark = marks.first, "-*_".contains(mark), marks.count >= 3 else { return false }
    return marks.allSatisfy { $0 == mark } && leading(line) <= 3
  }

  /// The `===` or `---` under a heading's text.
  private static func isUnderline(_ line: Substring) -> Bool {
    let marks = line.trimmingCharacters(in: .whitespaces)
    guard let mark = marks.first, mark == "=" || mark == "-" else { return false }
    return marks.allSatisfy { $0 == mark } && leading(line) <= 3
  }

  /// The row under a table's header.
  private static func isDelimiter(_ line: Substring) -> Bool {
    line.contains("-") && line.contains("|") && line.allSatisfy { "|:- \t".contains($0) }
  }

  /// `[name]: link`, which a link elsewhere in the reply refers to.
  private static func isReference(_ line: Substring) -> Bool {
    let rest = line.drop { $0 == " " }
    guard leading(line) <= 3, rest.first == "[", let close = rest.firstIndex(of: "]") else { return false }
    return close > rest.index(after: rest.startIndex) && rest[rest.index(after: close)...].first == ":"
  }

  private static func leading(_ line: Substring) -> Int {
    line.prefix { $0 == " " }.count
  }

  /// A fenced code block's opening line, which the same run of backticks or tildes, at least as long, closes.
  private struct Fence {
    let mark: Character
    let length: Int
    let isFormula: Bool

    init?(_ line: Substring) {
      let rest = line.drop { $0 == " " }
      guard line.count - rest.count <= 3, let mark = rest.first, mark == "`" || mark == "~" else { return nil }
      let run = rest.prefix { $0 == mark }.count
      guard run >= 3 else { return nil }
      self.mark = mark
      length = run
      isFormula = rest.dropFirst(run).trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("math")
    }

    func closes(_ line: Substring) -> Bool {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      return trimmed.count >= length && trimmed.allSatisfy { $0 == mark }
    }
  }
}
