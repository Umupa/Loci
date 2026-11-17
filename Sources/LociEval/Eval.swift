import Foundation
import LociAgents
import LociHost
import LociModel

/// `swift run LociEval [--scenario ID]... [--model ID] [--no-judge] [--out DIR]`
///
/// Creates each scenario's mentor on Pi in a fresh Loci folder, waits for its first lesson, asks the probe,
/// then scores what it made: automatic checks, and the rubric of 0.11's judge, also on Pi.
@main
enum Eval {
  static let defaultModel = "sub2api/DeepSeek-V4.1-Flash-1017"

  static func main() async {
    do {
      try await run(Options(CommandLine.arguments.dropFirst()))
    } catch {
      say("eval failed: \(error)")
      exit(1)
    }
  }

  static func run(_ options: Options) async throws {
    let programs = AgentPrograms(search: await AgentSearch.forThisMac())
    guard let judge = programs.driver(for: .pi) else { throw EvalError.noAgent(.pi) }
    try FileManager.default.createDirectory(at: options.out, withIntermediateDirectories: true)
    var rows: [Row] = []
    for scenario in options.scenarios {
      say("\(scenario.id): creating the mentor")
      let root = FileManager.default.temporaryDirectory.appending(path: "loci-eval-\(UUID().uuidString)")
      defer { try? FileManager.default.removeItem(at: root) }
      let host = try await LocalHost.start(
        root: root, database: root.appending(path: "loci.sqlite"),
        environment: .system(defaultProvider: .pi, defaultModel: options.model))
      let evidence = try await Runner(host: host, root: root).run(scenario)
      await host.close()
      let checks = Checks(evidence)
      var verdict: Verdict?
      if options.judge {
        say("\(scenario.id): judging")
        let folder = root.appending(path: "judge")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        verdict = try await Judge.verdict(
          Judge.prompt(evidence, checks: checks), driver: judge, model: options.model, folder: folder)
      }
      let row = Row(scenario: scenario.id, checks: checks, verdict: verdict)
      try save(row, evidence: evidence, to: options.out.appending(path: scenario.id))
      rows.append(row)
    }
    let summary = Summary.markdown(rows, model: options.model)
    try Data(summary.utf8).write(to: options.out.appending(path: "summary.md"))
    say(summary)
  }

  private static func save(_ row: Row, evidence: Evidence, to folder: URL) throws {
    try FileManager.default.createDirectory(at: folder.appending(path: "lessons"), withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try encoder.encode(row).write(to: folder.appending(path: "score.json"))
    try encoder.encode(evidence.conversation).write(to: folder.appending(path: "conversation.json"))
    for lesson in evidence.lessons {
      try Data(lesson.body.utf8).write(to: folder.appending(path: "lessons/\(lesson.slug).md"))
    }
  }

  static func say(_ text: String) {
    FileHandle.standardError.write(Data((text + "\n").utf8))
  }
}

struct Row: Codable, Sendable {
  let scenario: String
  let checks: Checks
  let verdict: Verdict?
}

struct Options {
  var scenarios = Scenario.all
  var model: String? = Eval.defaultModel
  var judge = true
  var out = URL(filePath: "output/eval").appending(path: Timestamp(.now).description)

  init(_ arguments: some Sequence<String>) throws(EvalError) {
    var chosen: [Scenario] = []
    var rest = Array(arguments)[...]
    while let flag = rest.popFirst() {
      switch flag {
      case "--no-judge":
        judge = false
      case "--scenario", "--model", "--out":
        guard let value = rest.popFirst() else { throw .usage("\(flag) needs a value") }
        if flag == "--model" { model = value }
        if flag == "--out" { out = URL(filePath: value) }
        if flag == "--scenario" {
          guard let scenario = Scenario.all.first(where: { $0.id == value }) else {
            throw .usage("no scenario \(value); there are \(Scenario.all.map(\.id).joined(separator: ", "))")
          }
          chosen.append(scenario)
        }
      default:
        throw .usage("unknown option \(flag)")
      }
    }
    if !chosen.isEmpty { scenarios = chosen }
  }
}

enum Summary {
  static func markdown(_ rows: [Row], model: String?) -> String {
    let items = Verdict.items
    var lines = [
      "# Mentor evaluation", "", "Mentors and judge on Pi, model `\(model ?? "Pi's default")`.", "",
      "| Scenario | Catalog | First lesson | Lessons (written) | Links (first-party) | Locators | Failed | "
        + items.joined(separator: " | ") + " | Mean |",
      "|" + String(repeating: " --- |", count: 8 + items.count),
    ]
    for row in rows {
      let checks = row.checks
      let scores = items.map { item in row.verdict?.scores[item].map { String($0.score) } ?? "—" }
      lines.append(
        "| \(row.scenario) | \(minutes(checks.catalogAfterSeconds)) | \(minutes(checks.firstLessonAfterSeconds)) | "
          + "\(checks.plannedLessons) (\(checks.writtenLessons)) | \(checks.links) (\(checks.firstPartyLinks)) | "
          + "\(checks.locators) | \(checks.failedTurns) | " + scores.joined(separator: " | ") + " | "
          + (row.verdict.map { String(format: "%.1f", $0.mean) } ?? "—") + " |")
    }
    for row in rows {
      if let worst = row.verdict?.worst { lines += ["", "- \(row.scenario): \(worst)"] }
    }
    return lines.joined(separator: "\n") + "\n"
  }

  private static func minutes(_ seconds: Double?) -> String {
    seconds.map { String(format: "%.1fm", $0 / 60) } ?? "—"
  }
}
