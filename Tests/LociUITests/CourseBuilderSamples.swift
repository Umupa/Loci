import Foundation
import LociModel

@testable import LociUI

/// The Raft course from the design, at each point of its building.
enum BuilderSamples {
  static let raft = EntityID()

  static let said: [(loci: Bool, text: String)] = [
    (false, "Raft"), (true, "学 Raft 是为了什么？"), (false, "面试要讲清楚"), (true, "面试官总会往下挖。"),
    (true, "你最怕被追问到哪一步？"), (false, "旧任期的日志"),
  ]

  static func question(
    _ text: String, _ options: [(String, String)], multiple: Bool = false,
    purpose: CourseQuestion.Purpose = .followUp(field: nil)
  ) throws -> CourseQuestion {
    let drafted = try CourseQuestion.Draft(
      question: text, options: options.map { try CourseQuestion.Option(title: $0.0, detail: $0.1) },
      multiple: multiple, purpose: purpose)
    return CourseQuestion(id: EntityID(), draft: drafted)
  }

  static func firstQuestion() throws -> CourseQuestion {
    try question(
      "学 Raft 是为了什么？",
      [
        ("面试要讲清楚", "被追问时能一路讲到底层"), ("工作里要选型", "在 etcd、Consul 和自研之间做决定"), ("排查线上问题", "脑裂、选举风暴时知道先看哪"),
        ("单纯好奇", "想知道分布式系统怎么不乱"),
      ], purpose: .followUp(field: .purpose))
  }

  static func known() throws -> CourseQuestion {
    try question(
      "这些里面，哪些你已经有把握？", [("多数派", "任两个多数必有交集"), ("状态机复制", "同样的命令同样的顺序"), ("Paxos", "另一种共识"), ("逻辑时钟", "用计数代替钟")],
      multiple: true,
      purpose: .followUp(field: .known))
  }

  static func restated() throws -> CourseQuestion {
    try question(
      "我理解的是：面试里把 Raft 讲到底层，重点是分区时为什么不会脑裂；多数派和逻辑时钟不用从头讲。对吗？", [("对，就这样", "去找资料"), ("改一下", "再说说哪里不对")],
      purpose: .confirmation)
  }

  static let goalWords = ["面试里讲清 Raft，被追问时讲到底层", "最怕被问：分区时会不会有两个领导", "已经有把握：多数派、逻辑时钟", "讲清原理和取舍，不读代码", "十课，每课八分钟"]

  static func goal(_ lines: Int, subtitle: Bool = false) throws -> CourseGoal {
    func line(_ index: Int) -> String? { index < lines ? goalWords[index] : nil }
    return try CourseGoal(
      title: "Raft", subtitle: subtitle ? "一群机器怎么对一串日志达成一致" : nil, purpose: line(0), focus: line(1), known: line(2),
      depth: line(3), length: line(4))
  }

  static func asking() throws -> BuilderShown {
    BuilderShown(stage: .goal, fraction: 0.1, title: "Raft", goal: try goal(0), question: try firstQuestion())
  }

  static func ticking() throws -> BuilderShown {
    BuilderShown(stage: .goal, fraction: 0.4, title: "Raft", goal: try goal(2), question: try known())
  }

  static func confirming() throws -> BuilderShown {
    BuilderShown(stage: .goal, fraction: 0.7, title: "Raft", goal: try goal(4), question: try restated())
  }

  static func sealed() throws -> BuilderShown {
    BuilderShown(
      stage: .goal, fraction: 1, title: "Raft", goal: try goal(5, subtitle: true), sealed: true, canGoOn: true)
  }

  static let sourceIDs = (0..<6).map { _ in EntityID() }

  static let sources: [SourceShown] = [
    .init(
      id: sourceIDs[0], title: "In Search of an Understandable Consensus Algorithm", kind: .paper,
      detail: "raft.github.io · 2014", read: 1),
    .init(
      id: sourceIDs[1], title: "Designing for Understandability: the Raft Consensus Algorithm", kind: .video,
      detail: "youtube.com · 52:10", read: 1),
    .init(
      id: sourceIDs[2], title: "Consensus: Bridging Theory and Practice", kind: .paper, detail: "stanford.edu · 2014",
      read: nil),
    .init(
      id: sourceIDs[3], title: "etcd-io/raft", kind: .repository, detail: "github.com · Go", commit: "4abf9f2c81",
      read: 1),
    .init(id: sourceIDs[4], title: "etcd 的一致性保证", kind: .page, detail: "etcd.io · docs", read: 0.25),
    .init(id: sourceIDs[5], title: "Paxos Made Simple", kind: .paper, detail: "lamport.org · 2001"),
  ]

  static func gathering() throws -> BuilderShown {
    BuilderShown(
      stage: .sources, fraction: 0.7, working: true, title: "Raft", goal: try goal(5, subtitle: true), sealed: true,
      sources: sources)
  }

  static let titles = [
    "共识是在解决什么", "多数派必有交集", "任期是逻辑时钟", "随机超时打破平票", "日志匹配的归纳", "只靠计数提交当前任期", "成员一次只变一台", "快照截断日志",
    "etcd 把 Raft 做成库", "面试里怎么讲 Raft",
  ]

  static let lessonIDs = titles.indices.compactMap { Lesson.ID("l\($0)") }

  static func lessons(written: Int, writing: Bool) -> [LessonLine] {
    titles.enumerated().map { index, title in
      let state: LessonLine.State =
        index < written ? .written(minutes: [8, 7, 9][index % 3]) : index == written && writing ? .writing : .planned
      return LessonLine(id: lessonIDs[index], title: title, state: state)
    }
  }

  static let leaves = [
    Leaf(
      number: 1, title: "共识是在解决什么",
      paragraphs: ["五台机器，每台都可能宕机、变慢、丢消息。它们要对同一串命令达成一致：同样的顺序，一条不多，一条不少。", "难的不是复制，是在谁都可能掉线时，仍然只有一个版本的历史。"],
      writing: false),
    Leaf(
      number: 2, title: "多数派必有交集",
      paragraphs: ["五台里任取三台，再任取三台，两组至少共用一台。一条日志只要写进过多数，之后任何一次选举的多数里都有人记得它。", "Raft 所有的安全性，"], writing: true),
  ]

  /// A lesson long past what its page holds, its last paragraph still being written.
  static let longLeaf = Leaf(
    number: 3, title: "任期是逻辑时钟",
    paragraphs: [
      "每台机器都有一个任期号，从 1 开始往上数。谁发起选举，谁就先把自己的任期加一。",
      "收到的消息里任期比自己大，就说明自己落后了：立刻承认对方，退回跟随者。",
      "收到的任期比自己小，就说明对方落后了：拒绝它，并把自己的任期告诉它。",
      "所以任期不靠墙上的钟，只靠比较大小。网络再乱，大小关系不会乱。",
      "一个任期里最多只有一个领导者，因为当选要拿到多数票，而两个多数必有交集。",
      "有的任期一个领导者也没有：票分散了，超时之后进入下一个任期重来。",
      "日志里的每一条都带着写下它时的任期。比较两份日志谁更新，先比最后一条的任期，",
    ], writing: true)

  static func writing() throws -> BuilderShown {
    BuilderShown(
      stage: .writing, fraction: 0.1, working: true, title: "Raft", goal: try goal(5, subtitle: true), sealed: true,
      sources: sources, lessons: lessons(written: 1, writing: true), leaf: leaves[1], canGoOn: true)
  }
}
