import Markdown

/// Who a bubble is from.
enum Speaker: Equatable {
  case loci, person
}

/// How a conversation's messages become bubbles.
enum BubbleLayout {
  /// A reply split where its writer left a blank line, as short messages sent one after another. A code
  /// block, list, table, quote or formula stays whole in one bubble, blank lines inside it and all.
  static func bubbles(in reply: String) -> [String] {
    let markdown = DisplayMath.fenced(reply)
    let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)
    var bubbles: [ClosedRange<Int>] = []
    for block in Document(parsing: markdown).children {
      guard let range = block.range else { continue }
      let span = (range.lowerBound.line - 1)...Self.lastLine(of: range)
      if let last = bubbles.last, !blankLine(between: last, and: span, in: lines) {
        bubbles[bubbles.count - 1] = last.lowerBound...span.upperBound
      } else {
        bubbles.append(span)
      }
    }
    return bubbles.map { span in
      lines[span.clamped(to: 0...(lines.count - 1))].joined(separator: "\n")
    }
  }

  /// The index of a block's last line. A list's range ends at the start of the line after it, which is
  /// not part of it.
  private static func lastLine(of range: SourceRange) -> Int {
    let ends = range.upperBound
    let endsBefore = ends.column == 1 && ends.line > range.lowerBound.line
    return ends.line - (endsBefore ? 2 : 1)
  }

  private static func blankLine(
    between earlier: ClosedRange<Int>, and later: ClosedRange<Int>, in lines: [Substring]
  ) -> Bool {
    guard earlier.upperBound + 1 < later.lowerBound else { return false }
    return lines[(earlier.upperBound + 1)..<later.lowerBound].contains {
      $0.allSatisfy(\.isWhitespace)
    }
  }
}
