import Foundation
import LociModel

/// `follows.json` at the top of the Loci folder: who the person follows. A file, so the follows outlive the
/// database; their episodes are in the database and are read again.
extension Store {
  static let followsFile = "follows.json"

  private var followsURL: URL { root.appending(path: Self.followsFile) }

  /// The follows in the order they were followed; none when the file is missing or cannot be read.
  public func follows() -> [Follow] {
    (try? decodeJSON([Follow].self, at: followsURL)) ?? []
  }

  /// Rewrites `follows.json` with the change, and gives the follows after it.
  @discardableResult
  public func changeFollows(_ change: (inout [Follow]) throws -> Void) throws -> [Follow] {
    var follows = follows()
    try change(&follows)
    try write(Formats.document(follows), to: followsURL)
    return follows
  }
}
