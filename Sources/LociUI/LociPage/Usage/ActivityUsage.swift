import Foundation
import LociModel

/// One row of the usage table: an activity's sessions in the span, added up (US-S4, US-S6, US-S7).
struct ActivityUsage: Identifiable {
  /// Oldest first, as the trend draws them.
  let sessions: [SessionUsage]
  let tokens: TokenCounts

  init(_ sessions: [SessionUsage]) {
    self.sessions = sessions.sorted { $0.startedAt < $1.startedAt }
    tokens = sessions.reduce(.zero) { $0 + $1.tokens }
  }

  var id: UsageActivity { sessions[0].activity }
  var activity: UsageActivity { id }
  var kind: UsageKind { UsageKind(activity) }
  var title: String? { sessions.last?.title }
  var model: String? { sessions.last?.model }
  var newest: Timestamp { sessions.last?.startedAt ?? Timestamp(millisecondsSince1970: 0) }
  var fresh: Int { tokens.fresh }
  var perSession: Int { fresh / sessions.count }
  var start: Int { sessions.reduce(0) { $0 + $1.context.start } / sessions.count }
  var typical: Int { UsageReport.median(sessions.map(\.context.end)) }
  var peak: Int { sessions.map(\.context.peak).max() ?? 0 }
  var hit: Double { UsageReport.hit(tokens) }
  var calls: Double { Double(sessions.reduce(0) { $0 + $1.calls }) / Double(sessions.count) }

  /// How much the context grew with each call, on average over the sessions that made more than one.
  var growth: Int {
    let grown = sessions.filter { $0.calls > 1 }.map { ($0.context.end - $0.context.start) / ($0.calls - 1) }
    return grown.isEmpty ? 0 : grown.reduce(0, +) / grown.count
  }

  /// What the context is made of, averaged over the sessions.
  var makeup: [ContextPart] { UsageReport.average(sessions.map(\.makeup)) }

  /// What the last runs came to, oldest first; `nil` for a conversation.
  var outcomes: [UsageOutcome]? {
    activity.isBackground ? Array(sessions.compactMap(\.outcome).suffix(Self.shownRuns)) : nil
  }

  static let shownRuns = 12

  var flags: [UsageFlag] {
    var flags: [UsageFlag] = []
    if typical > 0, Double(start) / Double(typical) > 0.5 { flags.append(.heavyStart(Double(start) / Double(typical))) }
    if peak > UsageFlag.largeContext { flags.append(.largeContext(peak)) }
    if tokens.cacheRead + tokens.input > 0, hit < UsageFlag.lowestHit { flags.append(.lowCache(hit)) }
    if let outcomes {
      let streak = outcomes.reversed().prefix { $0 == .nothingNew }.count
      let idle = outcomes.filter { $0 == .nothingNew }.count
      if streak >= UsageFlag.idleStreak {
        flags.append(.idleStreak(streak))
      } else if outcomes.count >= UsageFlag.fewestRuns, Double(idle) / Double(outcomes.count) >= UsageFlag.idleShare {
        flags.append(.idleShare(idle, of: outcomes.count))
      }
    }
    return flags
  }
}

/// A figure the page marks amber, with why (US-S7).
enum UsageFlag: Hashable {
  /// The context before any work is more than half the typical one.
  case heavyStart(Double)
  case largeContext(Int)
  case lowCache(Double)
  /// The last runs in a row that wrote nothing.
  case idleStreak(Int)
  /// Runs that wrote nothing, of the runs shown.
  case idleShare(Int, of: Int)

  static let largeContext = 200_000
  static let lowestHit = 0.8
  static let idleStreak = 3
  static let idleShare = 0.4
  /// How many runs the share of idle ones needs before it means anything.
  static let fewestRuns = 5

  /// The figure the flag marks.
  enum Figure {
    case perSession, cacheRead, fresh, outcomes
  }

  var figure: Figure {
    switch self {
    case .heavyStart: .perSession
    case .largeContext: .cacheRead
    case .lowCache: .fresh
    case .idleStreak, .idleShare: .outcomes
    }
  }
}
