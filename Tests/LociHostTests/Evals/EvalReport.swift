import Foundation

/// `report.md` and `results.json` for the groups that ran: a line for each day, then a line for each run.
enum EvalReport {
  static func write(_ outcomes: [EvalOutcome], runtime: String, to folder: URL) throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data(markdown(outcomes, runtime: runtime).utf8).write(to: folder.appending(path: "report.md"))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try encoder.encode(outcomes).write(to: folder.appending(path: "results.json"))
  }

  static func markdown(_ outcomes: [EvalOutcome], runtime: String) -> String {
    let verdicts = outcomes.flatMap(\.verdicts)
    let runs = outcomes.flatMap(\.runs)
    let passed = verdicts.filter(\.passed).count
    var text = "# 后台 run 评测\n\nruntime：\(runtime)　通过 \(passed) / \(verdicts.count) 天\n\n## 每天\n\n"
    text += "| 组 | 天 | 结果 | 原因 |\n|---|---:|---|---|\n"
    for verdict in verdicts {
      let reasons = verdict.reasons.joined(separator: "；").replacingOccurrences(of: "|", with: "\\|")
      text += "| \(verdict.group) | \(verdict.day) | \(verdict.passed ? "PASS" : "FAIL") | \(reasons) |\n"
    }
    text += "\n## 每个 run\n\n| 组 | 天 | 应用时间 | 结果 | 耗时 | token | 小结 |\n|---|---:|---|---|---:|---:|---|\n"
    for run in runs {
      let seconds = run.cost.map { String(format: "%.0fs", $0.seconds) } ?? "-"
      let tokens = run.cost?.tokens.map(String.init) ?? "-"
      let summary = (run.summary ?? "").replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(
        of: "\n", with: " ")
      text += "| \(run.group) | \(run.day) | \(run.at) | \(run.outcome) | \(seconds) | \(tokens) | \(summary) |\n"
    }
    let seconds = runs.compactMap(\.cost?.seconds).reduce(0, +)
    let tokens = runs.compactMap(\.cost?.tokens).reduce(0, +)
    text += "\n合计：run 耗时 \(String(format: "%.0f", seconds)) 秒，token \(tokens)（每个 run 最后一轮报告的数）。\n"
    return text
  }
}
