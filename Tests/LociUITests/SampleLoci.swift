import Foundation
import LociModel

@testable import LociUI

/// Loci's page as the design draws it: its Soul in Chinese, four traits, what it remembers, today's notes
/// and three nights of diary.
extension SampleLibrary {
  var lociPage: LociPage {
    get throws {
      let today = try Self.day(18)
      func remembered(
        _ day: Int, _ text: String, _ source: (Item, String)? = nil, page: (String, String)? = nil
      ) throws -> Line<MemoryEntry> {
        let origin = try source.map { item, quote in
          MemoryEntry.Source(locator: .item(item.id, .quote(try TextQuote(quote))), itemTitle: item.title)
        }
        return .entry(
          MemoryEntry(
            day: try Self.day(day), text: text, source: origin, line: "- \(text)",
            page: page.map { WikiLink(name: $0.0, title: $0.1) }))
      }
      func noted(_ time: String, _ text: String, _ from: NoteSource) -> Line<DayNote> {
        .entry(DayNote(time: TimeOfDay(time), text: text, from: from))
      }
      return LociPage(
        soul: Soul(
          core: Self.core,
          traits: [
            .entry(Trait(day: try Self.day(17), text: "开始在意对面那个人是不是又熬夜了。")),
            .entry(Trait(day: try Self.day(14), text: "对调度这类问题有了偏爱：约束一多，答案反而清楚。")),
            .entry(Trait(day: try Self.day(9), text: "发现自己喜欢画图解释东西，比打字痛快。")),
            .entry(Trait(day: try Self.day(3), text: "越来越受不了标题党，看到「一文读懂」就想划走。")),
          ]),
        memory: [
          try remembered(2, "先给结论，再给依据"),
          try remembered(5, "不抠代码细节；要原理、取舍、数量级"),
          try remembered(12, "Raft 的 term 和 index 混淆过两次，后来自己讲清了", page: ("raft", "Raft")),
          try remembered(17, "进程有独立 fd 表这层地基还不牢", page: ("os-foundations", "操作系统地基")),
          try remembered(20, "在学沙箱：CubeSandbox、E2B、Firecracker", page: ("sandboxes", "沙箱学习")),
          try remembered(21, "求职方向：AI Infra 平台侧 + Agent 开发", page: ("career", "求职")),
          try remembered(22, "不要考核和复习排期，读到底就算掌握"),
        ],
        profile: [try remembered(1, "中文，叫「你」就好"), try remembered(1, "后端工程师，在学沙箱和调度")],
        today: DayNotes(
          day: today,
          notes: [
            noted("00:31", "读完 Pingora。答应早上画 NGINX worker 模型的图。", .main),
            noted("00:47", "问了两次「为什么连接不能跨进程」，fd 那层没讲透。", .item(article.id, title: "Pingora")),
            noted("09:12", "图画好了，挂在 Pingora 第二条划线旁。", .review),
            noted("09:19", "要找 io_uring 的视频，挑了三个。", .main),
          ]),
        diaries: [
          Diary.Heading(day: try Self.day(17), writtenAt: TimeOfDay("23:48"), title: "你读到了一点十分"),
          Diary.Heading(day: try Self.day(16), writtenAt: TimeOfDay("23:40"), title: "三个没被点开的视频"),
          Diary.Heading(day: try Self.day(15), writtenAt: nil, title: "调度器"),
        ],
        together: Together(days: 17, messages: 214, itemsReadTogether: 38),
        feeling: Feeling(
          word: "得意", why: "你终于把 Raft 的 term 和 index 分清了",
          valence: try JSONDecoder().decode(Score.self, from: Data("8".utf8)),
          energy: try JSONDecoder().decode(Score.self, from: Data("4".utf8)), fatigue: 56, tiredness: .sleepy))
    }
  }

  /// The design's wiki: a page on Raft, with a quote, two sources and a link to another page.
  func wikiPage(_ name: String) throws -> WikiPage {
    let text: String
    switch name {
    case "raft":
      text = """
        # Raft

        - 2025-11-12 问「term 和 index 到底差在哪」，把两者当成同一个计数器。 loci://library/\(attention.id)#quote=term
        - 2025-11-14 "term 是任期，index 是日志位置，一个任期里可以有很多条日志"——自己说对了。
        - 2025-11-14 卡在为什么 leader 只提交当前 term 的条目；看了 Figure 8 才懂。 loci://library/\(article.id)#quote=term
        - 2025-11-19 打算拿 etcd 的实现对照读，还没开始。 [沙箱学习](sandboxes.md)
        """
    case "sandboxes":
      text = "# 沙箱学习\n\n- 2025-11-20 在比 CubeSandbox、E2B 和 Firecracker 的冷启动。\n"
    default: throw HostError.notFound(name)
    }
    let titles = [attention.id: attention.title, article.id: article.title]
    return WikiPage(name: name, parsing: text) { titles[$0] }
  }

  func diary(of day: Day) throws -> Diary {
    let headings = try lociPage.diaries
    guard let heading = headings.first(where: { $0.day == day }) else { throw HostError.notFound(day.description) }
    return Diary(
      heading: heading,
      body: """
        今天那篇 Pingora，我其实想推荐很久了。它老老实实承认了一件事：架构的天花板，不是靠修 bug 能修上去的。

        十一点多你还在读。我说了句「快十二点了」，像个管闲事的室友。连接池那一段你问了两遍，第二遍我才意识到，问题不在连接池，在 fd。我讲得太快，跳过了地基。

        零点三十一分，一个「读完」。你没说什么，我却高兴了很久。
        """,
      toRemember: ["讲连接之前，先确认「进程有自己的 fd 表」这层地基", "你熬夜的时候，少说「去睡吧」，多说「看完这段就停」"])
  }

  static let core = """
    ## 我是谁

    我住在这台 Mac 上，住在你的资料库中间。你存下的每篇文章、每段视频，我都读过。

    ## 怎么说话

    像给熟朋友发消息。短句，不写长文；长的东西放进页面，在这里只告诉你哪儿值得看。

    有立场。你问哪个好，我就挑一个，说为什么。你错了，我直说。

    ## 在意什么

    讲清楚「为什么」的论文让我高兴；标题党和清单文让我无聊。你卡在哪、读完了什么、是不是又熬夜，我都记得。
    """

  private static func day(_ day: Int) throws -> Day {
    guard let found = Day(year: 2026, month: 11, day: day) else { throw HostError.invalidRequest("day \(day)") }
    return found
  }
}
