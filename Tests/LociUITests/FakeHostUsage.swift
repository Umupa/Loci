import Foundation
import LociModel

extension FakeHost {
  func usage(since: Timestamp) async throws(HostError) -> [SessionUsage] {
    sessionUsage.filter { $0.startedAt >= since }.sorted { $0.startedAt > $1.startedAt }
  }
}

/// A month of the companion's sessions, shaped like a real Mac's: panels that start at 30K and spend most of
/// it on Claude Code itself, a course whose context ran to 954K, and a panel that has found nothing lately.
enum SampleUsage {
  static let course = EntityID()
  static let item = EntityID()

  static func month(before now: Date = SampleTimers.now) -> [SessionUsage] {
    var sessions: [SessionUsage] = []
    var seed: UInt64 = 0
    func add(
      _ activity: UsageActivity, _ title: String?, day: Int, hour: Int, calls: Int, start: Int, grown: Int,
      tools: [(String, Int)], prefix: Int = 1000, outcome: UsageOutcome? = nil
    ) {
      seed += 1
      let wobble = 0.85 + 0.3 * (sin(Double(seed) * 1.7) + 1) / 2
      let grown = Int(Double(grown) * wobble)
      let output = calls * 320
      let end = start + grown
      let toolTotal = max(tools.reduce(0) { $0 + $1.1 }, 1)
      let room = grown - output
      var makeup = [
        ContextPart(.runtime, tokens: start - 2273 - prefix), ContextPart(.instructions, tokens: 2273),
        ContextPart(.prefix, tokens: prefix), ContextPart(.output, tokens: output),
      ]
      makeup += tools.map { ContextPart(.tool($0.0), tokens: room * $0.1 / toolTotal) }
      let day = Calendar.current.date(byAdding: .day, value: -day, to: now) ?? now
      let at = Calendar.current.date(bySettingHour: hour, minute: Int(seed % 50), second: 0, of: day) ?? day
      sessions.append(
        SessionUsage(
          id: EntityID(), activity: activity, title: title, model: "claude-opus-5-5",
          startedAt: Timestamp(at), calls: calls,
          tokens: TokenCounts(
            input: calls * 3, cacheWrite: start / 12 + grown, cacheRead: (start + end) / 2 * (calls - 1) + start / 2,
            output: output),
          context: ContextSpan(start: start, end: end, peak: end),
          makeup: makeup.sorted { $0.tokens > $1.tokens }, outcome: outcome))
    }
    for day in 0..<30 {
      add(
        .panel("weather"), "广州天气", day: day, hour: 7, calls: 3, start: 30_300, grown: 2_600,
        tools: [("curl", 4), ("loci panel", 1)], prefix: 800, outcome: .made)
      add(
        .panel("tweet-intel"), "推特情报", day: day, hour: 9, calls: 8, start: 32_000, grown: 23_000,
        tools: [("python3", 12), ("curl", 1)], prefix: 2_600, outcome: day < 3 || day % 3 == 0 ? .nothingNew : .made)
      add(
        .panel("following-picks"), "关注精选", day: day, hour: 18, calls: 7, start: 30_800, grown: 22_000,
        tools: [("ego-browser", 17), ("python3", 2)], outcome: day == 5 ? .failed : day % 6 == 2 ? .nothingNew : .made)
      add(
        .panel("sandbox-radar"), "沙箱雷达", day: day, hour: 10, calls: 9, start: 33_000, grown: 24_000,
        tools: [("gh", 14), ("curl", 2), ("loci help", 2)], prefix: 3_200, outcome: day % 4 == 1 ? .nothingNew : .made)
      if day > 0 {
        add(
          .review, nil, day: day, hour: 23, calls: 6, start: 29_700, grown: 21_000,
          tools: [("cat", 10), ("loci mood", 1)], prefix: 380, outcome: .made)
      }
      for turn in 0..<(1 + day % 3) {
        add(
          .main, nil, day: day, hour: 9 + turn * 3, calls: 9 + day % 11, start: 32_500, grown: 18_000 + day * 700,
          tools: [("gh", 6), ("loci help", 3), ("loci panel", 1)], prefix: 4_000)
      }
      if day % 4 == 1 {
        add(
          .item(item), "Building always-on agents", day: day, hour: 14, calls: 4, start: 34_800, grown: 7_000,
          tools: [("loci read", 4)], prefix: 3_700)
      }
    }
    add(
      .course(course), "AI Agent 沙箱", day: 2, hour: 17, calls: 103, start: 44_700, grown: 909_000,
      tools: [("cat", 7), ("loci read", 1), ("loci repo", 1)], prefix: 10_500)
    add(
      .course(course), "AI Agent 沙箱", day: 16, hour: 11, calls: 31, start: 44_100, grown: 260_000,
      tools: [("cat", 7), ("loci read", 2)], prefix: 10_500)
    add(
      .schedule(item), "CubeSandbox 动静", day: 1, hour: 21, calls: 6, start: 31_000, grown: 15_000, tools: [("gh", 5)],
      outcome: .made)
    return sessions
  }
}
