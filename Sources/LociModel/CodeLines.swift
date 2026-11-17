/// Some lines of one file in a repository, at one commit.
///
/// Written `path=<path>&L=<first>[-<last>]&rev=<commit>`.
public struct CodeLines: Hashable, Sendable {
  /// Relative to the repository root, with no empty, `.` or `..` components.
  public let path: String
  /// Counted from 1.
  public let lines: ClosedRange<Int>
  public let commit: CommitID

  public init(path: String, lines: ClosedRange<Int>, commit: CommitID) throws {
    let components = path.split(separator: "/", omittingEmptySubsequences: false)
    guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
      throw ModelError("not a path inside the repository: \(path)")
    }
    guard lines.lowerBound >= 1 else { throw ModelError("lines are counted from 1") }
    self.path = path
    self.lines = lines
    self.commit = commit
  }

  init?(path: String, taking fragment: inout Fragment) {
    guard let range = fragment.take("L").flatMap(Self.lineRange),
      let commit = fragment.take("rev").flatMap(CommitID.init),
      let lines = try? CodeLines(path: path, lines: range, commit: commit)
    else { return nil }
    self = lines
  }

  var fragment: String {
    let range = lines.count == 1 ? "\(lines.lowerBound)" : "\(lines.lowerBound)-\(lines.upperBound)"
    return Fragment.join([("path", path), ("L", range), ("rev", commit.description)])
  }

  private static func lineRange(_ text: String) -> ClosedRange<Int>? {
    let bounds = text.split(separator: "-", omittingEmptySubsequences: false).map { Int(digits: String($0)) }
    guard (1...2).contains(bounds.count), let first = bounds[0], let last = bounds[bounds.count - 1], first <= last
    else { return nil }
    return first...last
  }
}
