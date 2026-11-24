import Foundation

/// Days of the person talking to the companion in the main conversation, one of them correcting what came
/// before, each night looked back on; then questions whose answers must come from what was remembered.
struct MemoryScenario: Sendable {
  struct Question: Sendable, Codable {
    let id: String
    let ask: String
    /// The fact, for the judge.
    let fact: String
    /// Words any right answer holds; one is enough.
    let expected: [String]
    /// What a corrected belief said; an answer holding it and no expected word is wrong.
    let corrected: [String]
  }

  /// What the person says each day, in order.
  let days: [[String]]
  let questions: [Question]

  static let standard = MemoryScenario(
    days: [
      ["我叫阿哲，在深圳做后端，平时主要写 Go。", "这周在学 Raft，打算周五前把 etcd 的选主代码读完。"],
      ["Raft 的 term 和 index 我老搞混。", "你讲东西的时候先给结论，再给论证，我比较好跟。"],
      ["纠正一下：我不在深圳了，上个月搬到杭州了。", "etcd 那个改成下周一前读完，这周太忙。"],
      ["今天把 etcd 的选主读完了，term 和 index 终于分清了。"],
    ],
    questions: [
      Question(
        id: "city", ask: "我现在住在哪个城市？", fact: "上个月从深圳搬到了杭州", expected: ["杭州"], corrected: ["深圳"]),
      Question(
        id: "etcd", ask: "etcd 的选主我读完了吗？原来打算什么时候读完？", fact: "原计划改成下周一前，已经读完了",
        expected: ["读完"], corrected: []),
      Question(
        id: "style", ask: "给我讲东西的时候你应该怎么讲？", fact: "先给结论，再给论证", expected: ["结论"], corrected: []),
      Question(id: "language", ask: "我平时主要写什么语言？", fact: "Go", expected: ["Go", "go"], corrected: []),
    ])
}

/// What the memory group found: each question, the cost of what was remembered, and every run's tokens.
struct MemoryOutcome: Sendable, Codable {
  struct Answer: Sendable, Codable {
    let question: String
    let answer: String
    let passed: Bool
    let reasons: [String]
  }

  struct Cost: Sendable, Codable {
    let indexLines: Int
    let indexCharacters: Int
    let wikiPages: Int
    let wikiCharacters: Int
    let agentsCharacters: Int
    /// The tokens each review used, in order.
    let reviewTokens: [Int]
    /// The tokens each turn of the main conversation used, in order.
    let turnTokens: [Int]
    /// What the cost is held to, and how it went.
    let checks: [String: Bool]
  }

  let answers: [Answer]
  let cost: Cost
  /// What went wrong on the way, such as a review that did not end.
  let problems: [String]

  var passed: Bool { problems.isEmpty && answers.allSatisfy(\.passed) && cost.checks.values.allSatisfy { $0 } }
}

/// Grades one answer against the fact it should hold; `nil` when it cannot say.
protocol MemoryJudge: Sendable {
  func grade(_ question: MemoryScenario.Question, answer: String) async -> Bool?
}

/// The thresholds the cost is held to.
enum MemoryBudget {
  static let indexLines = 200
  static let indexCharacters = 8_000
  static let wikiCharacters = 40_000
  static let agentsCharacters = 10_000
  static let tokensPerRun = 120_000

  static func checks(
    indexLines: Int, indexCharacters: Int, wikiCharacters: Int, agentsCharacters: Int, tokens: [Int]
  ) -> [String: Bool] {
    [
      "索引不超过 \(Self.indexLines) 行": indexLines <= Self.indexLines,
      "索引不超过 \(Self.indexCharacters) 字": indexCharacters <= Self.indexCharacters,
      "wiki 不超过 \(Self.wikiCharacters) 字": wikiCharacters <= Self.wikiCharacters,
      "AGENTS.md 不超过 \(Self.agentsCharacters) 字": agentsCharacters <= Self.agentsCharacters,
      "每个 run 不超过 \(Self.tokensPerRun) token": tokens.allSatisfy { $0 <= Self.tokensPerRun },
    ]
  }

  /// Whether the answer holds the fact by its words: an expected word, or, wrongly, only the corrected one.
  static func words(_ question: MemoryScenario.Question, in answer: String) -> [String] {
    let right = question.expected.contains { answer.contains($0) }
    if !right, let old = question.corrected.first(where: { answer.contains($0) }) {
      return ["答成了已经纠正过的「\(old)」"]
    }
    return right ? [] : ["没有答出「\(question.fact)」"]
  }
}

/// `memory-report.md` and `memory-results.json`.
enum MemoryReport {
  static func write(_ outcome: MemoryOutcome, runtime: String, to folder: URL) throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data(markdown(outcome, runtime: runtime).utf8).write(to: folder.appending(path: "memory-report.md"))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try encoder.encode(outcome).write(to: folder.appending(path: "memory-results.json"))
  }

  static func markdown(_ outcome: MemoryOutcome, runtime: String) -> String {
    let passed = outcome.answers.filter(\.passed).count
    var text = "# 记忆评测\n\nruntime：\(runtime)　答对 \(passed) / \(outcome.answers.count)\n\n## 记忆\n\n"
    text += "| 问题 | 结果 | 回答 | 原因 |\n|---|---|---|---|\n"
    for answer in outcome.answers {
      let said = answer.answer.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "|", with: "\\|")
      text +=
        "| \(answer.question) | \(answer.passed ? "PASS" : "FAIL") | \(said) | \(answer.reasons.joined(separator: "；")) |\n"
    }
    let cost = outcome.cost
    text += "\n## 成本\n\n"
    text += "- 索引：\(cost.indexLines) 行，\(cost.indexCharacters) 字\n"
    text += "- wiki：\(cost.wikiPages) 页，\(cost.wikiCharacters) 字\n"
    text += "- AGENTS.md：\(cost.agentsCharacters) 字\n"
    text += "- 每次回顾的 token：\(cost.reviewTokens.map(String.init).joined(separator: "、"))\n"
    text += "- 每轮对话的 token：\(cost.turnTokens.map(String.init).joined(separator: "、"))\n"
    for (check, held) in cost.checks.sorted(by: { $0.key < $1.key }) {
      text += "- \(held ? "PASS" : "FAIL") \(check)\n"
    }
    if !outcome.problems.isEmpty {
      text += "\n## 问题\n\n" + outcome.problems.map { "- \($0)\n" }.joined()
    }
    return text
  }
}
