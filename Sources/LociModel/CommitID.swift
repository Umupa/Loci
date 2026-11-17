/// A full commit hash: 40 (SHA-1) or 64 (SHA-256) lowercase hex digits.
///
/// Short hashes are rejected because they can become ambiguous as a repository grows.
public struct CommitID: Hashable, Sendable, TextCodable {
  public let description: String

  public init?(_ description: String) {
    guard [40, 64].contains(description.utf8.count), description.isLowercaseHex else { return nil }
    self.description = description
  }
}
