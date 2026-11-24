import Foundation

/// Asks the Codex on this Mac once per line, with `judge.md` beside this file, in a read-only sandbox and a
/// session it does not keep.
struct CodexJudge: EvalJudge {
  let codex: URL

  static let prompt = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "judge.md")

  func classify(_ line: String, among events: [EvalEvent], noise: [String]) async -> EvalJudgement {
    guard let template = try? String(contentsOf: Self.prompt, encoding: .utf8) else { return .none }
    let text =
      template
      .replacing("{{events}}", with: events.map { "- \($0.id): \($0.about)" }.joined(separator: "\n"))
      .replacing("{{noise}}", with: noise.joined(separator: ", "))
      .replacing("{{line}}", with: line)
    let answer = FileManager.default.temporaryDirectory.appending(path: "loci-eval-judge-\(UUID().uuidString).txt")
    defer { try? FileManager.default.removeItem(at: answer) }
    let process = Process()
    process.executableURL = codex
    process.arguments = [
      "exec", "--ephemeral", "--skip-git-repo-check", "--sandbox", "read-only", "--output-last-message", answer.path,
      text,
    ]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    let finished = await withCheckedContinuation { (done: CheckedContinuation<Bool, Never>) in
      process.terminationHandler = { done.resume(returning: $0.terminationStatus == 0) }
      do { try process.run() } catch { done.resume(returning: false) }
    }
    guard finished, let reply = try? String(contentsOf: answer, encoding: .utf8) else { return .none }
    return Self.judgement(in: reply)
  }

  /// The answer in `{"event": "…"}`, wherever the line puts it.
  static func judgement(in reply: String) -> EvalJudgement {
    guard let json = reply.firstMatch(of: /\{[^{}]*\}/).map({ Data($0.output.utf8) }),
      let object = try? JSONSerialization.jsonObject(with: json) as? [String: String], let event = object["event"]
    else { return .none }
    switch event {
    case "noise": return .noise
    case "none": return .none
    default: return .event(event)
    }
  }
}

/// Answers from a table, for the eval's own tests; a line not in it is about nothing.
struct FixedJudge: EvalJudge {
  var answers: [String: EvalJudgement] = [:]

  func classify(_ line: String, among events: [EvalEvent], noise: [String]) async -> EvalJudgement {
    answers[line] ?? .none
  }
}
