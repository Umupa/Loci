import LociModel
import LociStore

/// When a conversation's next turn needs a new agent session, and why.
enum SessionRotation {
  /// A session is full at this share of its context window. Agent CLIs compact by themselves at about
  /// 90–95%, losing what they choose; a new session starts earlier and is carried over by memory, notes
  /// and a recap of the conversation.
  static let fullShare = 0.75
  /// Taken as full when the window is not known: 75% of 200k, the smallest window in common use.
  static let fullTokens = 150_000
  /// Characters per token when nothing was reported and tokens are estimated: between English (about 4)
  /// and Chinese (about 1.5).
  static let charactersPerToken = 3

  enum Reason: Hashable, Sendable {
    /// The conversation has never had a session.
    case first
    /// The person started over.
    case startedOver
    case runtimeChanged
    /// `AGENTS.md` changed: the soul, the person, or the rules.
    case instructionsChanged
    /// The projects kept out of the chat's memory changed: what was said before may name one, so none of it is
    /// told again.
    case projectsKeptOut
    case full
    /// The agent could not find the session to continue.
    case lost

    /// Whether the new session is told what was said just before, so the person sees no seam.
    var carriesOver: Bool {
      switch self {
      case .first, .startedOver, .projectsKeptOut: false
      case .runtimeChanged, .instructionsChanged, .full, .lost: true
      }
    }
  }

  /// What a session has been through.
  struct Wear: Hashable, Sendable {
    var usage: ContextUsage?
    /// Characters sent and received, tool output included.
    var characters = 0
    var compacted = false
  }

  /// `nil` when the current session can go on. `current` is `nil` when there is none to go on with,
  /// which `startedOver` says was the person's doing.
  static func reason(
    current: SessionRecord?, startedOver: Bool, wear: Wear, runtime: Runtime, instructions: String
  ) -> Reason? {
    guard let current else { return startedOver ? .startedOver : .first }
    if keptOut(in: current.instructions) != keptOut(in: instructions) { return .projectsKeptOut }
    if current.runtime != runtime { return .runtimeChanged }
    if current.instructions != instructions { return .instructionsChanged }
    return isFull(wear) ? .full : nil
  }

  /// What a session is opened with, as kept with it: the fingerprint of its instructions, then, when any project
  /// is kept out of memory, that of those projects.
  static func fingerprint(of instructions: String, keptOut projects: String) -> String {
    Fingerprint.of(instructions) + (projects.isEmpty ? "" : "|" + Fingerprint.of(projects))
  }

  private static func keptOut(in fingerprint: String) -> Substring {
    fingerprint.split(separator: "|", maxSplits: 1).dropFirst().first ?? ""
  }

  static func isFull(_ wear: Wear) -> Bool {
    if wear.compacted { return true }
    if let used = wear.usage?.used {
      if let window = wear.usage?.window, window > 0 { return Double(used) / Double(window) >= fullShare }
      return used >= fullTokens
    }
    return wear.characters / charactersPerToken >= fullTokens
  }
}
