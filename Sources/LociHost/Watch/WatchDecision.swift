import Foundation
import LociModel

enum WatchDecision {
  case discard
  case panel(String, entry: String, summary: String)
  case escalate(key: String, summary: String, reason: String, evidence: [String], deadline: Timestamp)

  static func read(_ text: String, entries: [SourceEntry], panels: Set<String>) throws -> [Self] {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let words = trimmed.components(separatedBy: .newlines)
    let json =
      if words.first == "```json", words.last == "```" {
        words.dropFirst().dropLast().joined(separator: "\n")
      } else { trimmed }
    let output = try JSONDecoder().decode(Output.self, from: Data(json.utf8))
    let expected = Set(entries.map(\.id))
    var remaining = expected
    var snapshotSeen = false
    let decisions: [Self] = try output.decisions.map { result in
      if let id = result.id {
        guard remaining.remove(id) != nil else { throw Self.invalid }
      } else {
        guard !snapshotSeen else { throw Self.invalid }
        snapshotSeen = true
      }
      switch result.action {
      case "discard": return .discard
      case "panel":
        guard let panel = result.panel, panels.contains(panel), let entry = result.id,
          let summary = nonempty(result.summary)
        else { throw Self.invalid }
        return .panel(panel, entry: entry, summary: summary)
      case "escalate":
        guard let key = nonempty(result.key), key.utf8.count <= 160,
          let summary = nonempty(result.summary), let reason = nonempty(result.reason),
          let deadline = result.deadline.flatMap(Timestamp.parseISO8601),
          let evidence = result.evidenceIDs, Set(evidence).isSubset(of: expected),
          result.id.map(evidence.contains) != false
        else { throw Self.invalid }
        return .escalate(key: key, summary: summary, reason: reason, evidence: evidence, deadline: deadline)
      default: throw Self.invalid
      }
    }
    guard remaining.isEmpty else { throw Self.invalid }
    return decisions
  }

  private static func nonempty(_ text: String?) -> String? {
    guard let value = text?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
    return value
  }

  private static let invalid = HostError.invalidRequest("Watch triage gave an incomplete decision or unknown evidence.")

  private struct Output: Decodable {
    let decisions: [Decision]
  }

  private struct Decision: Decodable {
    let id: String?
    let action: String
    let panel: String?
    let key: String?
    let summary: String?
    let reason: String?
    let evidenceIDs: [String]?
    let deadline: String?
  }
}
