import Foundation
import LociModel

/// A CLI's session file read down to what its usage needs: the first message, and each call to the model with
/// what reached the session since the call before.
public struct SessionFile: Hashable, Sendable {
  /// The model the file says ran, when it says.
  public var model: String?
  /// The first message: Loci's prefix and what was asked.
  public var prompt: String = ""
  public var calls: [Call] = []
  /// Whether the session wrote anything through `loci` or by editing a file, rather than only reading.
  public var wrote = false

  public init() {}

  public struct Call: Hashable, Sendable {
    public var tokens: TokenCounts
    /// What the tools brought back since the call before, as estimated tokens by the label of each tool.
    public var results: [String: Int] = [:]
    /// Estimated tokens of what was said to the session since the call before, other than tool results.
    public var said = 0

    public init(tokens: TokenCounts, results: [String: Int] = [:], said: Int = 0) {
      self.tokens = tokens
      self.results = results
      self.said = said
    }
  }

  /// What the session cost and where its context came from. `instructions` is how many tokens `AGENTS.md`
  /// takes, which the CLI reads before the first call. The first call's context is split between the CLI,
  /// `AGENTS.md` and the first message; each later call's growth goes to the output of the call before, then
  /// to the tools and words that came in between, by their size.
  public func usage(instructions: Int) -> Usage? {
    guard let first = calls.first else { return nil }
    let contexts = calls.map(\.tokens.context)
    var prompt = TokenEstimate.of(self.prompt)
    var agents = instructions
    let room = first.tokens.context * 9 / 10
    if prompt + agents > room, prompt + agents > 0 {
      prompt = prompt * room / (prompt + agents)
      agents = room - prompt
    }
    var parts: [ContextSource: Int] = [
      .runtime: first.tokens.context - prompt - agents, .instructions: agents, .prefix: prompt,
    ]
    for index in calls.indices.dropFirst() {
      let grown = contexts[index] - contexts[index - 1]
      guard grown > 0 else { continue }
      let output = min(grown, calls[index - 1].tokens.output)
      parts[.output, default: 0] += output
      let rest = grown - output
      var weights = calls[index].results.map { (ContextSource.tool($0.key), $0.value) }
      weights.append((.talk, calls[index].said))
      let total = weights.reduce(0) { $0 + $1.1 }
      if total == 0 {
        parts[.talk, default: 0] += rest
      } else {
        for (source, weight) in weights where weight > 0 { parts[source, default: 0] += rest * weight / total }
      }
    }
    let makeup = parts.filter { $0.value > 0 }.map { ContextPart($0.key, tokens: $0.value) }
      .sorted { $0.tokens == $1.tokens ? "\($0.source)" < "\($1.source)" : $0.tokens > $1.tokens }
    return Usage(
      model: model, calls: calls.count, tokens: calls.reduce(.zero) { $0 + $1.tokens },
      context: ContextSpan(start: first.tokens.context, end: contexts.last ?? 0, peak: contexts.max() ?? 0),
      makeup: makeup, wrote: wrote)
  }

  /// A session's usage, before Loci says what the session was for.
  public struct Usage: Hashable, Sendable {
    public let model: String?
    public let calls: Int
    public let tokens: TokenCounts
    public let context: ContextSpan
    public let makeup: [ContextPart]
    public let wrote: Bool
  }
}

/// About how many tokens a text takes: one for each CJK character, and one for about every three and a half
/// other characters. Close enough to split a context into its parts; never used for what a session cost.
public enum TokenEstimate {
  public static func of(_ text: String) -> Int {
    var wide = 0
    var narrow = 0
    for scalar in text.unicodeScalars {
      switch scalar.value {
      case 0x3000...0x9FFF, 0xAC00...0xD7AF, 0xF900...0xFAFF, 0xFF00...0xFFEF: wide += 1
      default: narrow += 1
      }
    }
    return wide + (narrow * 2 + 6) / 7
  }
}
