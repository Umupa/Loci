import Foundation
import LociModel
import LociStore

/// Keeps `agent/feelings.json`: counts the messages that tire the companion, and changes its moods and
/// sleep when it says so through `loci`. Every change goes through here, so turns in two conversations
/// never write over each other.
actor FeelingsKeeper {
  private let store: Store
  private let environment: HostEnvironment
  private let follower: Follower

  init(store: Store, environment: HostEnvironment, follower: Follower) {
    self.store = store
    self.environment = environment
    self.follower = follower
  }

  /// How the companion feels in the main conversation now, for its page.
  func feeling() -> Feeling {
    let now = environment.now()
    var feelings = saved()
    feelings.fatigue.wakeIfRested(at: now, in: environment.timeZone)
    let shown = Self.felt(feelings, in: .main, at: now, timeZone: environment.timeZone)
    let felt = shown.felt
    return Feeling(
      word: felt.rests ? nil : felt.word, why: felt.rests ? nil : (felt.here ?? felt.base.mood).why,
      valence: felt.valence, energy: felt.energy, fatigue: shown.fatigue, tiredness: shown.tiredness)
  }

  /// A message came in, in `conversation`: how the companion feels as it reads it.
  func heard(in conversation: ConversationRef) async -> FeltNow {
    let now = environment.now()
    var feelings = saved()
    feelings.fatigue.heard(at: now, in: environment.timeZone)
    feelings.moods = feelings.moods.pruned(at: now)
    try? store.saveFeelings(feelings)
    await follower.follow([.loci(.feelings)])
    return Self.felt(feelings, in: conversation, at: now, timeZone: environment.timeZone)
  }

  /// Carries out what the companion said about how it feels, and says how it feels afterwards.
  func run(_ request: FeelingRequest, in conversation: ConversationRef?) async throws(HostError) -> String {
    let now = environment.now()
    var feelings = saved()
    feelings.fatigue.wakeIfRested(at: now, in: environment.timeZone)
    switch request {
    case .here(let word, let valence, let why):
      guard let conversation else { throw .invalidRequest(FeelingRequest.scopeMessage) }
      feelings.moods.conversations[conversation.tag] = Mood(word: word, valence: valence, why: why, at: now)
    case .base(let word, let valence, let energy, let why):
      feelings.moods.base = BaseMood(mood: Mood(word: word, valence: valence, why: why, at: now), energy: energy)
    case .sleep:
      feelings.fatigue.sleep(at: now)
    case .wake:
      feelings.fatigue.wake(at: now)
    }
    feelings.moods = feelings.moods.pruned(at: now)
    try attempt { try store.saveFeelings(feelings) }
    await follower.follow([.loci(.feelings)])
    return Self.felt(feelings, in: conversation ?? .main, at: now, timeZone: environment.timeZone).lines
      .joined(separator: "\n")
  }

  private func saved() -> Feelings {
    (try? store.feelings()) ?? Feelings()
  }

  private static func felt(
    _ feelings: Feelings, in conversation: ConversationRef, at now: Timestamp, timeZone: TimeZone
  )
    -> FeltNow
  {
    let (fatigue, tiredness) = feelings.fatigue.felt(at: now, in: timeZone)
    return FeltNow(felt: feelings.moods.felt(in: conversation, at: now), fatigue: fatigue, tiredness: tiredness)
  }
}

/// How the companion feels and how tired it is, as each message tells it.
struct FeltNow: Sendable {
  let felt: Felt
  let fatigue: Int
  let tiredness: Tiredness

  var lines: [String] {
    let base = felt.base
    return [
      "Feeling: \(felt.word), valence \(felt.valence.value)/10, energy \(felt.energy.value)/10",
      "  Base mood: \(base.mood.word), valence \(base.mood.valence.value)/10, energy \(base.energy.value)/10"
        + " — \(base.mood.why)",
      "  Here: " + (felt.here.map { "\($0.word), valence \($0.valence.value)/10 — \($0.why)" } ?? "nothing yet"),
      "Fatigue: \(fatigue)/100, \(tiredness.rawValue)",
    ]
  }
}
