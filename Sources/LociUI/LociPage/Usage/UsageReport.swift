import Foundation
import LociModel

/// How far back the usage page looks.
enum UsageSpan: Hashable, CaseIterable {
  case today, week, month

  var days: Int {
    switch self {
    case .today: 1
    case .week: 7
    case .month: 30
    }
  }
}

/// The kinds of activity the chart stacks and the legend lists.
enum UsageKind: Hashable, CaseIterable {
  case main, course, item, panel, timer, review

  init(_ activity: UsageActivity) {
    switch activity {
    case .main, .project: self = .main
    case .course: self = .course
    case .item: self = .item
    case .panel: self = .panel
    case .schedule, .followUp, .repair: self = .timer
    case .review: self = .review
    }
  }
}

/// The usage of the companion's sessions over a span, added up for the page (US-S2–US-S4).
struct UsageReport {
  /// The sessions in the span and of the chosen kind, newest first.
  let sessions: [SessionUsage]
  let tokens: TokenCounts
  let calls: Int
  /// The average context before any work: the CLI, `AGENTS.md` and the prefix.
  let start: [ContextPart]
  let typical: Int
  /// Each day of the span, or each hour of today, with its fresh tokens by kind; every kind, chosen or not.
  let buckets: [Bucket]
  /// Each kind's fresh tokens and sessions in the span, most first; every kind, chosen or not.
  let kinds: [KindTotal]
  /// The activities of the chosen kind, most fresh tokens first.
  let activities: [ActivityUsage]

  struct Bucket: Hashable {
    let start: Date
    let fresh: [UsageKind: Int]
    var total: Int { fresh.values.reduce(0, +) }
  }

  struct KindTotal: Hashable {
    let kind: UsageKind
    let fresh: Int
    let sessions: Int
  }

  init(_ usage: [SessionUsage], span: UsageSpan, kind chosen: UsageKind?, now: Date, calendar: Calendar) {
    let today = calendar.startOfDay(for: now)
    let since = calendar.date(byAdding: .day, value: 1 - span.days, to: today) ?? today
    let inSpan = usage.filter { $0.startedAt.date >= since }.sorted { $0.startedAt > $1.startedAt }
    sessions = inSpan.filter { chosen == nil || UsageKind($0.activity) == chosen }
    tokens = sessions.reduce(.zero) { $0 + $1.tokens }
    calls = sessions.reduce(0) { $0 + $1.calls }
    start = Self.average(sessions.map { $0.makeup.filter(\.source.isStart) })
    typical = Self.median(sessions.map(\.context.end))
    let starts: [Date] =
      span == .today
      ? (0..<24).compactMap { calendar.date(byAdding: .hour, value: $0, to: today) }
      : (0..<span.days).compactMap { calendar.date(byAdding: .day, value: $0, to: since) }
    buckets = starts.enumerated().map { index, start in
      let end = index + 1 < starts.count ? starts[index + 1] : .distantFuture
      let inside = inSpan.filter { $0.startedAt.date >= start && $0.startedAt.date < end }
      return Bucket(
        start: start, fresh: inside.reduce(into: [:]) { $0[UsageKind($1.activity), default: 0] += $1.tokens.fresh })
    }
    kinds = UsageKind.allCases.compactMap { kind in
      let ofKind = inSpan.filter { UsageKind($0.activity) == kind }
      return ofKind.isEmpty
        ? nil : KindTotal(kind: kind, fresh: ofKind.reduce(0) { $0 + $1.tokens.fresh }, sessions: ofKind.count)
    }
    .sorted { $0.fresh > $1.fresh }
    activities = Dictionary(grouping: sessions, by: \.activity).map { ActivityUsage($1) }
      .sorted { $0.fresh == $1.fresh ? $0.newest > $1.newest : $0.fresh > $1.fresh }
  }

  /// How much of the input came from the cache.
  var hit: Double { Self.hit(tokens) }

  static func hit(_ tokens: TokenCounts) -> Double {
    let read = tokens.cacheRead + tokens.input + tokens.cacheWrite
    return read == 0 ? 0 : Double(tokens.cacheRead) / Double(read)
  }

  static func median(_ values: [Int]) -> Int {
    values.isEmpty ? 0 : values.sorted()[values.count / 2]
  }

  /// The parts of many sessions' contexts, each the average over all of them, largest first.
  static func average(_ makeups: [[ContextPart]]) -> [ContextPart] {
    guard !makeups.isEmpty else { return [] }
    var sums: [ContextSource: Int] = [:]
    for part in makeups.joined() { sums[part.source, default: 0] += part.tokens }
    return sums.map { ContextPart($0.key, tokens: $0.value / makeups.count) }.filter { $0.tokens > 0 }
      .sorted { $0.tokens > $1.tokens }
  }
}

extension ContextSource {
  /// Whether the part is there before the session does anything.
  var isStart: Bool {
    switch self {
    case .runtime, .instructions, .prefix: true
    case .tool, .talk, .output: false
    }
  }
}
