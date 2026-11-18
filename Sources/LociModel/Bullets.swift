/// The list items of a Markdown file written by both Loci and the person, read forgivingly: an item is a
/// line starting `- ` or `* `, and lines indented under it continue it. Blank lines are left
/// out, and so is a `# ` title; any other line, other headings included, is kept as it is.
enum Bullets {
  enum Piece: Equatable {
    /// The item's first line as written, and its text with the bullet taken off and continuations joined.
    case item(line: String, text: String)
    case other(String)
  }

  static func pieces(of text: String) -> [Piece] {
    var pieces: [Piece] = []
    for raw in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
      let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.isEmpty { continue }
      if let item = item(in: line) {
        pieces.append(.item(line: line, text: item))
      } else if line.first == " " || line.first == "\t", case .item(let first, let so)? = pieces.last {
        pieces[pieces.count - 1] = .item(line: first, text: so + "\n" + trimmed)
      } else if trimmed.hasPrefix("# ") {
        continue
      } else {
        pieces.append(.other(line))
      }
    }
    return pieces
  }

  private static func item(in line: String) -> String? {
    guard line.hasPrefix("- ") || line.hasPrefix("* ") else { return nil }
    return line.dropFirst(2).trimmingCharacters(in: .whitespaces)
  }

  /// A leading `2026-11-18` and what follows it.
  static func leadingDay(_ text: String) -> (Day?, String) {
    guard let match = text.prefixMatch(of: /(\d{4}-\d\d-\d\d)(\s+|$)/), let day = Day(String(match.1)) else {
      return (nil, text)
    }
    return (day, String(text[match.range.upperBound...]))
  }
}
