import Foundation
import LociModel

@testable import LociUI

/// A few items, highlights on one of them, and one broken file.
struct Sample: Sendable {
  let borg: Item
  let items: [Item]
  let notes: [Note]
  var health: Health
  let runtime = Runtime(provider: .claudeCode, model: "opus", effort: .high)
  let text = """
    Large-scale cluster management at Google with Borg

    Google’s Borg system is a cluster manager that runs hundreds of thousands of jobs, from many thousands \
    of different applications, across a number of clusters each with up to tens of thousands of machines.

    It achieves high utilization by combining admission control, efficient task-packing, over-commitment, \
    and machine sharing with process-level performance isolation.
    """

  init(problems: Bool = true) throws {
    var entropy = Seeded()
    func id(_ offset: Double) -> EntityID {
      EntityID(at: Date(timeIntervalSince1970: 1_763_337_600 + offset), entropy: &entropy)
    }
    borg = try Self.item(id(3), .article, "Large-scale cluster management at Google with Borg", "en")
    items = [
      borg, try Self.item(id(4), .paper, "Firecracker: Lightweight Virtualization for Serverless", "en"),
      try Self.item(id(5), .article, "Kubernetes 调度框架：从 Filter 到 Score", "zh"),
      try Self.item(id(6), .article, "The Tail at Scale", "en"),
    ]
    let saved = Timestamp(millisecondsSince1970: 1_763_337_700_000)
    let borgID = borg.id
    func quote(_ text: String) throws -> Locator { .item(borgID, .quote(try TextQuote(text))) }
    notes = [
      try Note(
        id: id(10), locator: try quote("a cluster manager that runs hundreds of thousands of jobs"),
        excerpt: "a cluster manager that runs hundreds of thousands of jobs", savedAt: saved),
      try Note(
        id: id(11), locator: try quote("efficient task-packing, over-commitment"),
        excerpt: "efficient task-packing, over-commitment", thought: "装箱和超卖是利用率的两条腿。",
        exchanges: [
          try Note.Exchange(
            question: "超卖不怕把机器压垮吗？", answer: "超卖的是预留没用掉的部分；真用满时按优先级回收，低优先级的先让。",
            askedAt: Timestamp(millisecondsSince1970: 1_763_337_800_000))
        ], savedAt: Timestamp(millisecondsSince1970: 1_763_337_800_000)),
      try Note(
        id: id(12), locator: try quote("已经删掉的一句话"), excerpt: "已经删掉的一句话",
        savedAt: Timestamp(millisecondsSince1970: 1_763_337_900_000)),
    ]
    health = Health(
      database: .ready, readingStateLost: false,
      fileProblems: problems
        ? [
          FileProblem(
            path: "library/borg-019a8f1c/item.yaml", kind: .invalid, reason: "title: expected String",
            subject: .item(borg.id))
        ] : [])
  }

  private static func item(_ id: EntityID, _ kind: Item.Kind, _ title: String, _ language: String) throws -> Item {
    try Item(id: id, kind: kind, title: title, language: language)
  }

  struct Seeded: RandomNumberGenerator {
    var state: UInt64 = 7
    mutating func next() -> UInt64 {
      state &+= 0x9E37_79B9_7F4A_7C15
      return state ^ (state >> 31)
    }
  }
}
