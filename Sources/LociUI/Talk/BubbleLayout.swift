import Markdown

/// Who a bubble is from.
enum Speaker: Equatable {
  case loci, person
}

/// Where a bubble sits in a run of bubbles from the same speaker, which shapes its corners and decides
/// whether Loci's face is drawn beside it.
enum BubblePosition: Equatable {
  case alone, first, middle, last

  /// Only the last bubble of a run carries the face, as the last message of a chat does.
  var showsFace: Bool { self == .alone || self == .last }
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
      let span = (range.lowerBound.line - 1)...(range.upperBound.line - 1)
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

  /// Where each bubble sits in its run; `nil` in `speakers` is something else, such as a date or an event,
  /// which ends a run.
  static func positions(_ speakers: [Speaker?]) -> [BubblePosition?] {
    speakers.indices.map { index in
      guard let speaker = speakers[index] else { return nil }
      let continues = index > 0 && speakers[index - 1] == speaker
      let continued = index + 1 < speakers.count && speakers[index + 1] == speaker
      switch (continues, continued) {
      case (false, false): return .alone
      case (false, true): return .first
      case (true, true): return .middle
      case (true, false): return .last
      }
    }
  }

  /// Whether a bubble answers the other speaker's bubble just before it, which leaves a wider gap above it.
  static func turns(_ speakers: [Speaker?]) -> [Bool] {
    speakers.indices.map { index in
      guard index > 0, let speaker = speakers[index], let before = speakers[index - 1] else { return false }
      return before != speaker
    }
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
