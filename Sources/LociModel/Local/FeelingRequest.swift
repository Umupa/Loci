/// What the companion says about how it feels, through `loci mood`, `loci sleep` and `loci wake`. The reply
/// is how it feels afterwards, in a line.
public enum FeelingRequest: Hashable, Codable, Sendable {
  /// The mood in the conversation the session is in.
  case here(word: String, valence: Score, why: String)
  case base(word: String, valence: Score, energy: Score, why: String)
  case sleep
  case wake

  public static let scopeMessage = "loci mood here works only in a conversation; use loci mood base."
}
