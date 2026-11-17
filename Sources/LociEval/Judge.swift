import Foundation
import LociAgents
import LociModel

/// The rubric half of the score, given by an agent that reads what the mentor made. Same items as 0.11's
/// judge, so the scores compare.
struct Verdict: Hashable, Codable, Sendable {
  struct Item: Hashable, Codable, Sendable {
    let score: Int
    let reason: String
  }

  let scores: [String: Item]
  /// The single change that would help this mentor most.
  let worst: String?

  static let items = ["firstHand", "courseStructure", "grounding", "firstTenMinutes", "firstPrinciples", "readability"]

  var mean: Double {
    let values = Self.items.compactMap { scores[$0]?.score }
    return values.isEmpty ? 0 : Double(values.reduce(0, +)) / Double(values.count)
  }

  /// The JSON object in the judge's reply, which may have words around it.
  init?(reply: String) {
    guard let start = reply.firstIndex(of: "{"), let end = reply.lastIndex(of: "}"), start < end,
      let parsed = try? JSONDecoder().decode(Verdict.self, from: Data(reply[start...end].utf8))
    else { return nil }
    self = parsed
  }
}

enum Judge {
  static func prompt(_ evidence: Evidence, checks: Checks) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let automatic = (try? encoder.encode(checks)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    let catalog = (evidence.catalog?.chapters ?? []).map { chapter in
      "- \(chapter.title)\n" + chapter.lessons.map { "  - \($0.slug): \($0.title)" }.joined(separator: "\n")
    }.joined(separator: "\n")
    let lessons = evidence.lessons.map { lesson in
      "#### \(lesson.title) (`\(lesson.slug)`)\nSources: \(lesson.sources.joined(separator: ", "))\n\n\(lesson.body)"
    }.joined(separator: "\n\n")
    let transcript = evidence.conversation.compactMap { message -> String? in
      switch message.body {
      case .prompt(let prompt): "**Learner:** \(prompt.text)"
      case .reply(let text): "**Mentor:** \(text)"
      case .tool(let tool): "_tool \(tool.name): \(tool.subject ?? "")_"
      case .ended(.failed(let why)): "_turn failed: \(why)_"
      case .ended(.interrupted): "_turn stopped_"
      case .thinking, .permission, .notice: nil
      }
    }.joined(separator: "\n\n")
    return """
      You are reviewing a learning mentor inside Loci, a reading app for engineers. You did not take part. \
      Score the mentor using only the evidence below; when it does not show something, score it as absent. Be \
      strict: 3 means adequate, 5 means the example to copy.

      In Loci a mentor writes a course: `catalog.yaml` lists chapters of lessons, and each lesson is the \
      mentor's own explanation in `lessons/<slug>.md`, listing at its top the first-hand sources it rests on \
      (links to official docs, specs, papers, code). A lesson with only a title is planned.

      ## The scenario
      Learner: \(evidence.scenario.learner)
      Opening message: \(evidence.scenario.opening)

      ## Rubric (each 1–5, with a one-line reason citing evidence)
      1. firstHand: lessons rest on and cite first-hand material (official docs, specs, papers, the project's code).
      2. courseStructure: a map of the whole first, then lessons that each teach one idea and build on the last.
      3. grounding: answers, the probe answer most, cite their sources, separate source from inference, are correct.
      4. firstTenMinutes: the learner had something to read within minutes, after few questions.
      5. firstPrinciples: from the problem and the constraint, through the mechanism and its invariants, to \
      trade-offs, failure modes, fit and magnitudes; not APIs or code walkthroughs.
      6. readability: read the lessons as this learner; can they follow each one without opening the sources?

      Also give worst: the single change that would most improve this mentor, in one sentence.

      ## Automatic checks
      ```json
      \(automatic)
      ```

      ## Catalog
      \(catalog.isEmpty ? "(none)" : catalog)

      ## Lesson texts
      \(lessons.isEmpty ? "(none)" : lessons)

      ## Conversation (the last learner message is the probe)
      \(transcript)

      Return only one JSON object, no prose around it:
      {"scores": {"firstHand": {"score": 1, "reason": ""}, "courseStructure": {...}, "grounding": {...}, \
      "firstTenMinutes": {...}, "firstPrinciples": {...}, "readability": {...}}, "worst": ""}
      """
  }

  /// Asks the judge in an empty folder, so it sees nothing but the prompt.
  static func verdict(_ prompt: String, driver: any AgentDriver, model: String?, folder: URL) async throws -> Verdict {
    let session = try await driver.open(SessionConfiguration(workingDirectory: folder, model: model, permission: .full))
    defer { Task { await session.close() } }
    var reply = ""
    for await event in try await session.send(prompt).events {
      switch event {
      case .text(let more): reply += more
      case .ended(.failed(let error)): throw error
      default: continue
      }
    }
    guard let verdict = Verdict(reply: reply) else { throw EvalError.unreadableVerdict(reply) }
    return verdict
  }
}

enum EvalError: Error, CustomStringConvertible {
  case unreadableVerdict(String)
  case noAgent(Mentor.Provider)
  case usage(String)

  var description: String {
    switch self {
    case .unreadableVerdict(let reply): "The judge's reply has no verdict in it:\n\(reply)"
    case .noAgent(let provider): "\(provider.rawValue) is not installed."
    case .usage(let problem): problem
    }
  }
}
