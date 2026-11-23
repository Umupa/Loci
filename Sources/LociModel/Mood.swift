import Foundation

/// How strongly something is felt, a whole number from 0 to 10. A file that says more or less is read as
/// the nearest end.
public struct Score: Hashable, Comparable, Sendable, Codable {
  public static let range = 0...10
  public let value: Int

  /// `nil` outside 0 to 10.
  public init?(_ value: Int) {
    guard Self.range.contains(value) else { return nil }
    self.value = value
  }

  init(nearest value: Double) {
    self.value = min(max(Int(value.rounded(.toNearestOrAwayFromZero)), Self.range.lowerBound), Self.range.upperBound)
  }

  public init(from decoder: any Decoder) throws {
    self.init(nearest: Double(try decoder.singleValueContainer().decode(Int.self)))
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(value)
  }

  public static func < (lhs: Score, rhs: Score) -> Bool { lhs.value < rhs.value }
}

/// What the companion feels: a word for it, how good it feels from 0 to 10, why, and since when.
public struct Mood: Hashable, Codable, Sendable {
  public let word: String
  public let valence: Score
  public let why: String
  public let at: Timestamp

  public init(word: String, valence: Score, why: String, at: Timestamp) {
    self.word = word
    self.valence = valence
    self.why = why
    self.at = at
  }

  /// The mood `now`, its valence moved toward `resting` by the share of `span` that has passed; `nil` once
  /// the whole span has.
  func faded(toward resting: Score, over span: Int64, at now: Timestamp) -> Mood? {
    let passed = now.millisecondsSince1970 - at.millisecondsSince1970
    guard passed < span else { return nil }
    let share = Double(max(passed, 0)) / Double(span)
    let valence = Score(nearest: Double(valence.value) + Double(resting.value - valence.value) * share)
    return Mood(word: word, valence: valence, why: why, at: at)
  }
}

/// The base mood: one for the companion as a whole, with how much energy it has. Every conversation's mood
/// is pulled toward it.
public struct BaseMood: Hashable, Codable, Sendable {
  public let mood: Mood
  public let energy: Score

  public init(mood: Mood, energy: Score) {
    self.mood = mood
    self.energy = energy
  }

  /// How long a base mood lasts as it fades back to the resting one.
  public static let span: Int64 = 6 * 3_600_000

  /// What the companion is like when nothing has moved it: not neutral.
  public static let resting = (
    word: "cheerful", valence: Score(nearest: 6), energy: Score(nearest: 7),
    why: "curious, a little sharp-tongued, warm"
  )
}

/// The moods the companion keeps: the base mood and one per conversation, by the conversation's tag.
public struct Moods: Hashable, Codable, Sendable {
  public var base: BaseMood?
  public var conversations: [String: Mood]

  public init(base: BaseMood? = nil, conversations: [String: Mood] = [:]) {
    self.base = base
    self.conversations = conversations
  }

  /// How long a conversation's mood lasts as it fades back to the base mood.
  public static let conversationSpan: Int64 = 2 * 3_600_000

  /// What is felt in `conversation` at `now`.
  public func felt(in conversation: ConversationRef, at now: Timestamp) -> Felt {
    let resting = BaseMood.resting
    let lasting = base.flatMap { saved in
      saved.mood.faded(toward: resting.valence, over: BaseMood.span, at: now).map {
        BaseMood(mood: $0, energy: saved.energy)
      }
    }
    let base =
      lasting
      ?? BaseMood(
        mood: Mood(word: resting.word, valence: resting.valence, why: resting.why, at: now), energy: resting.energy)
    let here = conversations[conversation.tag]?.faded(
      toward: base.mood.valence, over: Self.conversationSpan, at: now)
    return Felt(base: base, here: here, rests: lasting == nil && here == nil)
  }

  /// The moods with those that have faded away left out.
  public func pruned(at now: Timestamp) -> Moods {
    Moods(
      base: base.flatMap {
        $0.mood.faded(toward: BaseMood.resting.valence, over: BaseMood.span, at: now) == nil ? nil : $0
      },
      conversations: conversations.filter {
        $0.value.at.millisecondsSince1970 + Self.conversationSpan > now.millisecondsSince1970
      })
  }
}

/// What the companion feels in one conversation at one moment.
public struct Felt: Hashable, Sendable {
  public let base: BaseMood
  /// The conversation's own mood, while it lasts.
  public let here: Mood?
  /// Whether nothing has moved the companion: it is its resting self.
  public let rests: Bool

  /// The word the conversation's mood gives, else the base mood's.
  public var word: String { here?.word ?? base.mood.word }

  /// The base mood weighs 0.3 and the conversation's 0.7.
  public var valence: Score {
    Score(nearest: Double(base.mood.valence.value) * 0.3 + Double((here ?? base.mood).valence.value) * 0.7)
  }

  public var energy: Score { base.energy }
}
