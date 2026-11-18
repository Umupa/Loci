import Foundation
import LociModel

@testable import LociUI

/// What the design shows inside the video, the podcast and the article.
extension SampleLibrary {
  static let videoLines: [(String, String, String)] = [
    ("10:31", "Pods that can't be placed right now wait in a separate queue.", "暂时放不下的 Pod 在另一个队列里等着。"),
    ("10:38", "They come back when something in the cluster changes.", "集群里有变化时，它们会被放回来。"),
    ("10:45", "So the active queue only holds pods worth trying.", "所以活动队列里只有值得一试的 Pod。"),
    ("10:52", "Every cycle starts by popping one pod off the active queue.", "每个周期都从活动队列里弹出一个 Pod 开始。"),
    (
      "10:58", "So every pod that lands in the queue goes through two phases before it's bound.",
      "每个进入队列的 Pod，在绑定之前都要经过两个阶段。"
    ),
    (
      "11:02", "First, filter plugins throw out every node that can't run the pod at all.",
      "首先，过滤插件剔除所有根本跑不了这个 Pod 的节点。"
    ),
    (
      "11:09", "Not enough CPU, a taint it doesn't tolerate, a volume in the wrong zone — that node is gone.",
      "CPU 不够、有它不容忍的污点、卷在别的可用区——这个节点就出局了。"
    ),
    ("11:18", "Then score plugins rank whatever survived, from zero to a hundred.", "然后打分插件给剩下的节点打分，从零到一百。"),
    (
      "11:26", "Here's what people miss: in a five-thousand-node cluster, we don't score all five thousand.",
      "大家常忽略的一点是：五千个节点的集群，并不会给五千个节点都打分。"
    ),
    (
      "11:35",
      "We stop filtering once we've found enough feasible nodes — a percentage that shrinks as the cluster grows.",
      "找到足够多的可行节点就停止过滤，这个比例随集群变大而变小。"
    ),
    ("11:46", "So the scheduler trades a perfect answer for a fast one, on purpose.", "所以调度器是有意用最优解换快速解。"),
    ("11:52", "For most workloads, the fifth-best node is just as good as the best.", "对大多数负载来说，第五好的节点和最好的节点一样好。"),
    ("12:04", "The cost of being slow is that every pod behind this one waits.", "慢的代价是排在它后面的每个 Pod 都得等。"),
    (
      "12:13", "We measured this on a cluster with five thousand nodes and a hundred and fifty thousand pods.",
      "我们在一个五千节点、十五万 Pod 的集群上测过。"
    ),
    (
      "12:20", "Throughput went from around thirty pods a second to well over three hundred.",
      "吞吐从每秒约 30 个 Pod 提升到 300 多个。"
    ),
    ("12:31", "Most of that came from not doing work, not from doing work faster.", "大部分提升来自少做事，而不是把事做得更快。"),
    ("12:39", "The second trick is that the binding cycle runs asynchronously.", "第二个办法是让绑定周期异步执行。"),
    (
      "12:46", "The pod is assumed onto the node while the API write happens in the background.",
      "API 写入在后台进行时，先假定 Pod 已在节点上。"
    ),
  ]

  static let recognizedLines: [(String, String)] = [
    ("19:30", "Now, what happens when nothing fits?"), ("19:34", "That's where preemption comes in."),
    ("19:38", "The scheduler looks for a node where evicting lower-priority pods would make room."),
    ("19:47", "It only ever considers pods with a lower priority than the one waiting."),
    ("19:55", "And it picks the node where the victims add up to the least disruption."),
    ("20:04", "Pod disruption budgets are respected, but only on a best-effort basis."),
    ("20:13", "If there's no way to stay within the budget, we'll still preempt, and that surprises people."),
    ("20:24", "So the nominated node gets recorded on the pod, and then"),
  ]

  static let podcastLines: [(String, Int, String, String)] = [
    (
      "18:02", 1, "So walk us through what actually happens when a request hits an inference server.",
      "那你带我们走一遍：一个请求打到推理服务器上，实际发生了什么？"
    ),
    (
      "18:08", 2, "The first thing is prefill: the whole prompt goes through the model in one big parallel pass.",
      "第一步是预填充：整段提示词一次性并行地过一遍模型。"
    ),
    (
      "18:14", 2, "Prefill is compute-bound. You're basically doing one giant matrix multiply.",
      "预填充受算力限制，基本上就是一次巨大的矩阵乘法。"
    ),
    ("18:21", 2, "Then decode starts, and decode is a completely different animal.", "然后开始解码，而解码完全是另一回事。"),
    (
      "18:31", 2, "Every new token reads the whole KV cache back from memory, so you're bound by bandwidth, not FLOPs.",
      "每生成一个 token 都要把整个 KV 缓存从显存读一遍，所以瓶颈是带宽，不是算力。"
    ),
    ("18:41", 3, "Which is why batching matters so much.", "这就是批处理这么重要的原因。"),
    (
      "18:45", 3,
      "If one token costs you a full read of the weights, you want as many users as possible sharing that read.",
      "既然一个 token 要把权重完整读一遍，就希望尽量多的用户共享这一次读取。"
    ),
    (
      "18:52", 2, "Exactly. Continuous batching lets new requests join between decode steps.",
      "没错。连续批处理让新请求可以在两次解码之间加入。"
    ),
    ("18:58", 2, "You don't wait for the slowest request in the batch to finish anymore.", "你不用再等批里最慢的那个请求结束了。"),
    ("19:04", 2, "The catch is memory: every request you add brings its own KV cache.", "代价是显存：每多加一个请求，就多一份 KV 缓存。"),
    ("19:10", 1, "And that is where paged attention comes in?", "这就是分页注意力登场的地方？"),
  ]

  static func time(_ text: String) -> Duration {
    .seconds(text.split(separator: ":").reduce(0) { $0 * 60 + (Int($1) ?? 0) })
  }

  /// `recognizing` gives the transcript as far as recognition has got, with no translation yet.
  func videoPage(recognizing: Bool = false) throws -> MediaPage {
    let lines: [(String, String, String)] =
      recognizing ? Self.recognizedLines.map { ($0.0, $0.1, "") } : Self.videoLines
    let segments = try lines.enumerated().map { index, line in
      let start = Self.time(line.0)
      let end = index + 1 < lines.count ? Self.time(lines[index + 1].0) : start + .seconds(6)
      return try Transcript.Segment(start: start, end: end, text: line.1)
    }
    let transcript = try Transcript(language: "en", origin: .platform, segments: segments)
    let translation = try Translation(language: "zh-Hans", lines: lines.map(\.2))
    let chapters = try [
      ("0:00", "调度器做什么"), ("3:40", "调度队列"), ("11:02", "过滤与打分"), ("12:20", "调度周期的扩展"), ("19:30", "抢占"),
      ("27:50", "问答"),
    ].map { try Outline.Chapter(start: Self.time($0.0), title: $0.1) }
    let highlights = try [("11:26", "11:52"), ("20:40", "21:30"), ("25:05", "25:40")].map {
      try Outline.Highlight(
        span: TimeSpan(start: Self.time($0.0), end: Self.time($0.1)), title: "取舍", reason: "调度器有意用最优换速度")
    }
    return MediaPage(
      transcript: transcript, translations: recognizing ? [] : [translation],
      outline: try Outline(chapters: chapters, highlights: highlights), hasCover: true, downloaded: true)
  }

  func podcastPage() throws -> MediaPage {
    let lines = Self.podcastLines
    let segments = try lines.enumerated().map { index, line in
      let start = Self.time(line.0)
      let end = index + 1 < lines.count ? Self.time(lines[index + 1].0) : start + .seconds(6)
      return try Transcript.Segment(start: start, end: end, text: line.2, speaker: line.1)
    }
    let chapters = try [("0:00", "开场"), ("6:10", "推理的两段"), ("31:00", "批处理"), ("48:30", "硬件")].map {
      try Outline.Chapter(start: Self.time($0.0), title: $0.1)
    }
    let highlights = try [("18:24", "18:40"), ("39:10", "40:30")].map {
      try Outline.Highlight(
        span: TimeSpan(start: Self.time($0.0), end: Self.time($0.1)), title: "带宽", reason: "解码受带宽限制")
    }
    return MediaPage(
      transcript: try Transcript(language: "en", origin: .recognized(.largeV3TurboQuantized), segments: segments),
      translations: [try Translation(language: "zh-Hans", lines: lines.map(\.3))],
      outline: try Outline(chapters: chapters, highlights: highlights), hasCover: true, downloaded: true)
  }

  static let articleText = """
    For years, the edge ran on NGINX. It served well, but as traffic grew the team kept hitting limits that came \
    from its architecture rather than from bugs they could fix.

    ## Why extending NGINX stopped working

    NGINX hands each request to a single worker process, so a connection pool inside one worker can't be reused by \
    another. On machines with many cores, that meant opening far more connections to origin servers than the \
    traffic needed.

    New features meant writing C modules, and a single memory-safety mistake could take down a worker serving \
    thousands of requests at once.

    ![The Cloudflare Blog](images/pingora.jpg)

    ## What Pingora does differently

    Pingora is written in Rust and runs on a multithreaded async runtime. Connections live in one shared pool, so \
    any thread can reuse a connection that another thread opened.

    In production it uses about 70% less CPU and 67% less memory than the service it replaced, while handling more \
    than a trillion requests a day.
    """
}
