import Foundation

/// What one agent CLI session cost, read from the file the CLI keeps of it: its tokens, how large its context
/// grew and what the context was made of.
public struct SessionUsage: Hashable, Codable, Sendable, Identifiable {
  public let id: EntityID
  public let activity: UsageActivity
  /// The name the activity goes by where Loci shows it: an item's, a course's, a panel's or a schedule's
  /// title; `nil` for the main conversation and the daily review, which the interface names itself.
  public let title: String?
  /// The model the CLI says it ran, or the one Loci asked for.
  public let model: String?
  public let startedAt: Timestamp
  /// How many times the CLI called the model.
  public let calls: Int
  public let tokens: TokenCounts
  public let context: ContextSpan
  /// Where the context came from, largest first; the parts add up to about `context.end`.
  public let makeup: [ContextPart]
  /// What a run in the background came to; `nil` for a conversation.
  public let outcome: UsageOutcome?

  public init(
    id: EntityID, activity: UsageActivity, title: String? = nil, model: String?, startedAt: Timestamp, calls: Int,
    tokens: TokenCounts, context: ContextSpan, makeup: [ContextPart], outcome: UsageOutcome? = nil
  ) {
    self.id = id
    self.activity = activity
    self.title = title
    self.model = model
    self.startedAt = startedAt
    self.calls = calls
    self.tokens = tokens
    self.context = context
    self.makeup = makeup
    self.outcome = outcome
  }
}

/// Tokens of one call or of many added up, as the providers count them.
public struct TokenCounts: Hashable, Codable, Sendable {
  /// Input the model read afresh, not from the cache.
  public var input: Int
  public var cacheWrite: Int
  public var cacheRead: Int
  public var output: Int

  public init(input: Int = 0, cacheWrite: Int = 0, cacheRead: Int = 0, output: Int = 0) {
    self.input = input
    self.cacheWrite = cacheWrite
    self.cacheRead = cacheRead
    self.output = output
  }

  public static let zero = TokenCounts()

  /// Tokens the model had not seen before: input, cache writes and output. Cache reads are counted apart.
  public var fresh: Int { input + cacheWrite + output }

  /// The context the call read: everything that went in, cached or not.
  public var context: Int { input + cacheWrite + cacheRead }

  public static func + (lhs: TokenCounts, rhs: TokenCounts) -> TokenCounts {
    TokenCounts(
      input: lhs.input + rhs.input, cacheWrite: lhs.cacheWrite + rhs.cacheWrite,
      cacheRead: lhs.cacheRead + rhs.cacheRead, output: lhs.output + rhs.output)
  }
}

/// How large a session's context was: at its first call, at its last, and at its largest.
public struct ContextSpan: Hashable, Codable, Sendable {
  public let start: Int
  public let end: Int
  public let peak: Int

  public init(start: Int, end: Int, peak: Int) {
    self.start = start
    self.end = end
    self.peak = peak
  }
}

/// A share of a session's context and where it came from.
public struct ContextPart: Hashable, Codable, Sendable {
  public let source: ContextSource
  public let tokens: Int

  public init(_ source: ContextSource, tokens: Int) {
    self.source = source
    self.tokens = tokens
  }
}

public enum ContextSource: Hashable, Codable, Sendable {
  /// What the CLI brings itself before Loci says anything: its own instructions and the tools it describes.
  case runtime
  /// The companion's `AGENTS.md`.
  case instructions
  /// The first message: Loci's prefix and what was asked.
  case prefix
  /// What one kind of tool call brought back, by the command or tool it ran: `gh`, `loci read`, `Read`.
  case tool(String)
  /// What was said after the first message.
  case talk
  /// What the model wrote, which every later call reads again.
  case output
}

/// What a session worked for, as the usage page groups sessions.
public enum UsageActivity: Hashable, Codable, Sendable {
  case main
  case item(EntityID)
  case course(EntityID)
  case project(Project.ID)
  /// Refreshing the panel by this name.
  case panel(String)
  case schedule(EntityID)
  case followUp(EntityID)
  case review
  /// Mending the source by this name.
  case repair(String)

  /// Whether the companion does it in the background, on its own, rather than in a conversation.
  public var isBackground: Bool {
    switch self {
    case .panel, .schedule, .followUp, .review, .repair: true
    case .main, .item, .course, .project: false
    }
  }
}

/// What a run in the background came to.
public enum UsageOutcome: Hashable, Codable, Sendable {
  /// It wrote something: a panel, the day's notes, a follow-up.
  case made
  /// It finished without writing anything.
  case nothingNew
  case failed
}

/// The usage of the companion's sessions that started at `since` or later, newest first. Sessions whose CLI
/// keeps no file Loci can read are left out.
public struct ReadUsage: RemoteCommand {
  public static let name = "usage.read"
  public let since: Timestamp

  public init(since: Timestamp) {
    self.since = since
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> [SessionUsage] {
    try await handler.usage(since: since)
  }
}
