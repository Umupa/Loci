import Foundation
import LociModel

@testable import LociUI

/// The highlights and conversations the design shows on the video, the podcast and the article.
extension SampleLibrary {
  private static func id(_ offset: Double, _ entropy: inout Sample.Seeded) -> EntityID {
    EntityID(at: Date(timeIntervalSince1970: 1_763_338_000 + offset), entropy: &entropy)
  }

  private static func stamp(_ date: Date) -> Timestamp {
    Timestamp(millisecondsSince1970: Int64(date.timeIntervalSince1970 * 1000))
  }

  /// Today or yesterday at a time, so the conversation reads «今天 21:04» whenever the snapshot is taken.
  static func moment(daysAgo: Int, _ hour: Int, _ minute: Int) -> Date {
    let calendar = Calendar.current
    let day = calendar.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
    return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
  }

  func notes(on item: EntityID) throws -> [Note] {
    var entropy = Sample.Seeded(state: 41)
    let saved = Timestamp(millisecondsSince1970: 1_763_338_000_000)
    func span(_ from: String, _ to: String) throws -> Locator {
      .item(item, .time(try TimeSpan(start: Self.time(from), end: Self.time(to))))
    }
    func quote(_ text: String) throws -> Locator { .item(item, .quote(try TextQuote(text))) }
    switch item {
    case video.id:
      return [
        try Note(
          id: Self.id(1, &entropy), locator: try span("11:46", "11:52"),
          excerpt: "So the scheduler trades a perfect answer for a fast one, on purpose.",
          exchanges: [
            try Note.Exchange(
              question: "这个比例默认是多少？", answer: "自适应：50% − 节点数 / 125，最低 5%；五千节点时约 10%。", mentor: scheduling.id,
              askedAt: saved)
          ], savedAt: saved),
        try Note(
          id: Self.id(2, &entropy), locator: try span("12:31", "12:39"),
          excerpt: "Most of that came from not doing work, not from doing work faster.", thought: "面试讲性能优化可以用这句开头",
          savedAt: saved),
        try Note(
          id: Self.id(3, &entropy), locator: try span("20:13", "20:24"),
          excerpt: "If there's no way to stay within the budget, we'll still preempt.", savedAt: saved),
      ]
    case podcast.id:
      return [
        try Note(
          id: Self.id(4, &entropy), locator: try span("18:31", "18:41"),
          excerpt:
            "Every new token reads the whole KV cache back from memory, so you're bound by bandwidth, not FLOPs.",
          exchanges: [
            try Note.Exchange(
              question: "为什么解码是带宽瓶颈？", answer: "读一遍 140 GB 权重约 40 毫秒，算一个 token 只要几毫秒。", mentor: system.id,
              askedAt: saved)
          ], savedAt: saved),
        try Note(
          id: Self.id(5, &entropy), locator: try span("18:58", "19:04"),
          excerpt: "You don't wait for the slowest request in the batch to finish anymore.", savedAt: saved),
      ]
    case article.id:
      let nginx =
        "NGINX hands each request to a single worker process, so a connection pool inside one worker can’t be reused by another."
      let pool = "Connections live in one shared pool, so any thread can reuse a connection that another thread opened."
      return [
        try Note(
          id: Self.id(6, &entropy), locator: try quote(nginx), excerpt: nginx,
          exchanges: [
            try Note.Exchange(
              question: "为什么不能跨 worker 共享连接？", answer: "连接是进程里的 fd，别的进程看不见；传 fd 的代价比新建还高。", mentor: system.id,
              askedAt: saved)
          ], savedAt: saved),
        try Note(
          id: Self.id(7, &entropy), locator: try quote(pool), excerpt: pool,
          exchanges: [
            try Note.Exchange(
              question: "共享池会不会让一个慢源站拖住所有线程？", answer: "池按源站分开、各有上限；等待是异步的，占住的是连接不是线程。", mentor: network.id,
              askedAt: saved)
          ], savedAt: saved),
        try Note(
          id: Self.id(8, &entropy), locator: try quote("70% less CPU and 67% less memory"),
          excerpt: "70% less CPU and 67% less memory", thought: "和多进程模型的内存重复有关？", savedAt: saved),
      ]
    default:
      return []
    }
  }

  func conversation(on item: EntityID) throws -> ItemConversation {
    var entropy = Sample.Seeded(state: 77)
    var messages: [AttributedMessage] = []
    func say(_ mentor: Mentor, _ date: Date, _ body: Message.Body) {
      messages.append(
        AttributedMessage(
          mentor: mentor.id,
          message: Message(id: Self.id(Double(messages.count), &entropy), at: Self.stamp(date), body: body)))
    }
    func ask(_ mentor: Mentor, _ date: Date, _ text: String, _ note: Note) {
      let passage = QuotedPassage(locator: note.locator, excerpt: note.excerpt ?? "", note: note.id)
      say(mentor, date, .prompt(Prompt(text: text, purpose: .chat, passage: passage)))
    }
    let notes = try notes(on: item)
    switch item {
    case video.id:
      let at = Self.moment(daysAgo: 0, 21, 4)
      ask(scheduling, at, "这个比例默认是多少？", notes[0])
      say(
        scheduling, at + 20,
        .reply(
          "默认是自适应的：`50% − 节点数 / 125`，最低 5%，并且至少要找到 100 个可行节点。\n\n五千节点时约 10%，找到 500 个可行节点就停。调大 `percentageOfNodesToScore` 换来的是更好的装箱，代价是每个 Pod 多等。"
        ))
      return ItemConversation(item: item, companion: scheduling.id, messages: messages, turn: nil)
    case podcast.id:
      let at = Self.moment(daysAgo: 0, 8, 12)
      ask(system, at, "为什么解码是带宽瓶颈？", notes[0])
      say(
        system, at + 20,
        .reply(
          "先算数量级：70B 模型的权重约 140 GB，H100 的显存带宽约 3.3 TB/s，光把权重读一遍就要 40 毫秒左右。\n\n而一个 token 的计算量只要几毫秒，算力大部分时间在等数据。批越大，同一次读取摊给越多请求。"
        ))
      return ItemConversation(item: item, companion: system.id, messages: messages, turn: nil)
    case article.id:
      let first = Self.moment(daysAgo: 1, 22, 30)
      ask(system, first, "为什么不能跨 worker 共享连接？", notes[0])
      say(
        system, first + 20,
        .reply(
          "worker 是独立的进程，各自有地址空间和文件描述符表。一条 TCP 连接就是某个进程里的一个 fd，别的进程看不见。\n\n可以用 `SCM_RIGHTS` 把 fd 传过去，但每次都要过一次内核，还得协调谁在用，代价比新建连接还高。"
        ))
      let second = Self.moment(daysAgo: 0, 9, 15)
      ask(network, second, "共享池会不会让一个慢源站拖住所有线程？", notes[1])
      say(
        network, second + 20,
        .reply("不会。池按源站分开、各有上限，慢源站只会耗尽自己那一份。\n\n等待是异步的：线程在等响应时去处理别的请求，被占住的只是连接，不是线程。"))
      return ItemConversation(item: item, companion: network.id, messages: messages, turn: nil)
    default:
      return ItemConversation(item: item, companion: nil, messages: [], turn: nil)
    }
  }
}
