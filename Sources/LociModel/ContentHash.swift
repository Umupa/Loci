/// The SHA-256 digest of an item's content, written `sha256:` followed by 64 lowercase hex digits.
public struct ContentHash: Hashable, Sendable, TextCodable {
  private static let prefix = "sha256:"

  public let description: String

  public init?(_ description: String) {
    guard description.hasPrefix(Self.prefix) else { return nil }
    let digest = description.dropFirst(Self.prefix.count)
    guard digest.utf8.count == 64, String(digest).isLowercaseHex else { return nil }
    self.description = description
  }
}
