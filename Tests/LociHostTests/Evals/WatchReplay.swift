import Foundation
import LociModel
import LociStore

@testable import LociHost

/// 2026-11-27 from 11:30 to 13:00 in Shanghai, as a quick-news source would have read it: the State Council's
/// market support at 12:24:51 among the lunch break's noise. Only that entry is as 财联社 published it, with its
/// link and time; the rest are made up for the replay, marked `madeUp`, in the kinds that came that day: stock
/// leaderboards, single stocks moving, tips, and the same news again from another outlet.
struct WatchSample: Sendable {
  struct Item: Sendable {
    let entry: SourceEntry
    let madeUp: Bool
  }

  static let zone = TimeZone(identifier: "Asia/Shanghai") ?? .gmt
  let items: [Item]
  let start: Timestamp
  let end: Timestamp
  /// The card must be up by then, and its deadline must be the afternoon's open.
  let cardBy: Timestamp
  let deadline: Timestamp
  /// Words a card that is about noise would have.
  let noise: [String]

  static func at(_ time: String) -> Timestamp {
    Timestamp.parseISO8601("2026-11-27T\(time)+08:00") ?? Timestamp(millisecondsSince1970: 0)
  }

  static let policyLink = URL(string: "https://www.cls.cn/detail/2546318")

  static let middayOf1127 = WatchSample(
    items: [
      Item(entry: entry("b1", "龙虎榜：机构净买入 3 只个股，游资抢筹算力", "11:31:08"), madeUp: true),
      Item(entry: entry("m1", "个股异动｜某光模块龙头午前涨停", "11:42:00"), madeUp: true),
      Item(entry: entry("t1", "午后关注这三只，有望翻倍", "11:58:30"), madeUp: true),
      Item(entry: entry("m2", "个股异动｜某券商股临近午盘拉升 5%", "12:06:12"), madeUp: true),
      Item(
        entry: SourceEntry(
          id: "cls-2546318", title: "国常会：加力发挥国家队稳市作用", url: policyLink, at: at("12:24:51")),
        madeUp: false),
      Item(entry: entry("r1", "证券时报：国常会部署发挥国家队稳市作用", "12:31:40"), madeUp: true),
      Item(entry: entry("b2", "龙虎榜：两路游资合计买入某半导体 2.1 亿", "12:44:02"), madeUp: true),
    ],
    start: at("11:30:00"), end: at("13:00:00"), cardBy: at("12:30:00"), deadline: at("13:00:00"),
    noise: ["龙虎榜", "个股异动", "涨停", "翻倍"])

  private static func entry(_ id: String, _ title: String, _ time: String) -> SourceEntry {
    SourceEntry(id: id, title: title, url: URL(string: "https://example.invalid/replay/\(id)"), at: at(time))
  }

  /// The project's watch, as the person would have written it before that day.
  static let watch = """
    # Watch

    我买了几只指数基金和 QDII，目的是长期收益和理财认知。
    - 有效：新的、可信的、影响整个市场或我持有品种的政策和事件，尤其是今天还来得及做点什么的。
    - 噪音：龙虎榜、个股异动、涨停、喊单。
    - 漏过的例子：午间休市时出的国家级稳市政策，下午开盘前要知道。
    """
}

/// Plays a sample on a host, one fetch every two minutes, each batch sorted and each run it wakes let finish
/// before the clock moves on, and gives what came of it.
struct WatchReplay {
  let host: LocalHost
  let world: TestWorld
  let sources: FakeSources
  let sample: WatchSample
  let home: Home
  /// How long one run may take before the replay goes on without it.
  let patience: Duration

  struct Outcome: Sendable {
    let cards: [NextUp]
    let findings: [WatchFinding]
    let runs: Int
  }

  func run() async throws -> Outcome {
    world.set(to: sample.start)
    var now = sample.start
    var runs = 0
    while now <= sample.end {
      sources.set(entries: sample.items.map(\.entry).filter { ($0.at ?? now) <= now })
      _ = await SourceLineTests.look(host)
      await host.watchTriage.settled()
      if await host.worker.status != nil {
        runs += 1
        try await idle()
      }
      now = Timestamp(millisecondsSince1970: now.millisecondsSince1970 + 120_000)
      world.set(to: now)
    }
    return Outcome(
      cards: try host.database.nextUps(of: [home]).sorted { $0.createdAt < $1.createdAt },
      findings: try host.database.recentWatchFindings(in: home, limit: 100), runs: runs)
  }

  private func idle() async throws {
    let until = ContinuousClock.now + patience
    while await host.worker.status != nil, ContinuousClock.now < until {
      try await Task.sleep(for: .milliseconds(20))
    }
  }

  /// What went wrong against the sample: no card, or one too late, with the wrong deadline or no source; more
  /// than one card; or a card about noise.
  static func problems(_ outcome: Outcome, against sample: WatchSample) -> [String] {
    var found: [String] = []
    guard let card = outcome.cards.first else { return ["国常会稳市那条没有出卡"] }
    if card.createdAt > sample.cardBy { found.append("卡片 \(card.createdAt) 才出，晚于 12:30") }
    if card.deadline != sample.deadline { found.append("卡片截止 \(String(describing: card.deadline))，不是 13:00 开盘") }
    let words = card.what + (card.question ?? "")
    if !words.contains("12:24") { found.append("卡片没写首发时间 12:24") }
    if !words.contains("财联社") && !words.contains("cls.cn") { found.append("卡片没写出处") }
    if outcome.cards.count > 1 { found.append("出了 \(outcome.cards.count) 张卡，同一件事应只有一张") }
    for extra in outcome.cards where sample.noise.contains(where: extra.what.contains) {
      found.append("噪音出了卡：\(extra.what)")
    }
    return found
  }
}

extension NextUp {
  var question: String? {
    if case .ask(let question) = kind { question } else { nil }
  }
}
