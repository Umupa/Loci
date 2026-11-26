import Foundation
import LociModel

extension ConnectorID {
  /// The connector a link in a reply opens, written `[words](loci://connectors/<id>)`, as Loci writes one when a
  /// connector needs connecting again.
  init?(link url: URL) {
    guard url.scheme?.lowercased() == "loci", url.host() == "connectors" else { return nil }
    let id = url.path().split(separator: "/").first.map(String.init) ?? ""
    guard id.wholeMatch(of: /[A-Za-z0-9._-]+/) != nil else { return nil }
    self.init(id)
  }
}

/// Replies written while Loci offered answers as buttons end with a fenced `loci-replies` block; it is not shown.
enum AnswerButtons {
  static func removed(from reply: String) -> String {
    var lines = reply.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    while let last = lines.last, last.allSatisfy(\.isWhitespace) { lines.removeLast() }
    guard let start = lines.lastIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "```loci-replies" }),
      lines[(start + 1)...].dropLast().allSatisfy({ $0.trimmingCharacters(in: .whitespaces) != "```" })
    else { return reply }
    lines.removeSubrange(start...)
    while let last = lines.last, last.allSatisfy(\.isWhitespace) { lines.removeLast() }
    return lines.joined(separator: "\n")
  }
}
