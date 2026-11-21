import Foundation

/// A reply's words apart from the answers Loci offers the person at its end: a fenced `loci-replies` block
/// closing the reply, one answer a line. The block never shows; at most two answers are offered.
struct QuickReplies: Equatable {
  /// The reply without the block.
  let text: String
  let replies: [String]

  static let fence = "```loci-replies"
  static let most = 2

  init(_ reply: String) {
    var lines = reply.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    while let last = lines.last, last.allSatisfy(\.isWhitespace) { lines.removeLast() }
    let partial = lines.last.map(Self.isPartialFence) ?? false
    if partial { lines.removeLast() }
    guard let start = lines.lastIndex(where: { Self.trimmed($0) == Self.fence }) else {
      text = partial ? Self.joined(lines) : reply
      replies = []
      return
    }
    var body = Array(lines[(start + 1)...])
    if let close = body.firstIndex(where: { Self.trimmed($0) == "```" }) {
      guard close == body.count - 1 else {
        text = reply
        replies = []
        return
      }
      body.removeLast()
    }
    text = Self.joined(Array(lines[..<start]))
    replies = Array(body.map(Self.trimmed).filter { !$0.isEmpty }.prefix(Self.most))
  }

  /// The start of the fence as it streams in, before the line is whole.
  private static func isPartialFence(_ line: String) -> Bool {
    let line = trimmed(line)
    return line.count > 3 && line != fence && fence.hasPrefix(line)
  }

  private static func trimmed(_ line: String) -> String {
    line.trimmingCharacters(in: .whitespaces)
  }

  private static func joined(_ lines: [String]) -> String {
    var lines = lines
    while let last = lines.last, last.allSatisfy(\.isWhitespace) { lines.removeLast() }
    return lines.joined(separator: "\n")
  }
}
