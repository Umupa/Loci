import Foundation

/// A version as releases are numbered: three numbers, optionally followed by a pre-release such as `-alpha.1`.
/// A pre-release comes before the release it leads to.
public struct ReleaseVersion: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
  public let major: Int
  public let minor: Int
  public let patch: Int
  public let preRelease: String?

  /// Reads `1.2.0`, `v1.2.0` or `1.0.0-alpha.1`; anything else is `nil`.
  public init?(_ text: String) {
    let bare = text.hasPrefix("v") ? text.dropFirst() : Substring(text)
    guard let match = bare.wholeMatch(of: /(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?/),
      let major = Int(match.1), let minor = Int(match.2), let patch = Int(match.3)
    else { return nil }
    self.major = major
    self.minor = minor
    self.patch = patch
    preRelease = match.4.map(String.init)
  }

  public var description: String {
    "\(major).\(minor).\(patch)" + (preRelease.map { "-\($0)" } ?? "")
  }

  public static func < (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
    let left = [lhs.major, lhs.minor, lhs.patch]
    let right = [rhs.major, rhs.minor, rhs.patch]
    if left != right { return left.lexicographicallyPrecedes(right) }
    switch (lhs.preRelease, rhs.preRelease) {
    case (let left?, let right?): return left.compare(right, options: .numeric) == .orderedAscending
    case (.some, nil): return true
    default: return false
    }
  }
}
