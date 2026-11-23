/// How the companion feels in the main conversation and how tired it is, as its page shows them.
public struct Feeling: Hashable, Codable, Sendable {
  /// The companion's own word for it; `nil` when nothing has moved it and it is its resting self.
  public let word: String?
  public let why: String?
  public let valence: Score
  public let energy: Score
  /// 0 to 100.
  public let fatigue: Int
  public let tiredness: Tiredness

  public init(word: String?, why: String?, valence: Score, energy: Score, fatigue: Int, tiredness: Tiredness) {
    self.word = word
    self.why = why
    self.valence = valence
    self.energy = energy
    self.fatigue = fatigue
    self.tiredness = tiredness
  }
}
