import Foundation

/// One background session that did one or more events from the inbox, and what came of it. Its record is
/// `agent/runs/<day>/<id>.md`.
public struct Run: Hashable, Codable, Sendable, Identifiable {
  public typealias ID = EntityID
  public let id: ID
  public let kind: Kind
  public let startedAt: Timestamp
  public let outcome: Outcome
  /// `runs/<day>/<id>.md`, relative to `agent/`.
  public let record: String

  /// The most tries a run gets before it is given up on.
  public static let tries = 3

  public init(id: ID, kind: Kind, startedAt: Timestamp, outcome: Outcome, record: String) {
    self.id = id
    self.kind = kind
    self.startedAt = startedAt
    self.outcome = outcome
    self.record = record
  }

  public func with(_ outcome: Outcome) -> Run {
    Run(id: id, kind: kind, startedAt: startedAt, outcome: outcome, record: record)
  }

  public enum Kind: Hashable, Codable, Sendable {
    /// Schedules, follow-ups and panels' refreshes that came due together.
    case timers(Timed)
    case review(Day)

    public var sources: [Event.Source] {
      switch self {
      case .timers(let timed): timed.sources
      case .review(let day): [.review(day)]
      }
    }
  }

  /// The events a timers run does: at least one, so a run of nothing cannot be made.
  public struct Timed: Hashable, Codable, Sendable {
    public let first: Event.Source
    public let rest: [Event.Source]

    public init(_ first: Event.Source, _ rest: [Event.Source] = []) {
      self.first = first
      self.rest = rest
    }

    public var sources: [Event.Source] { [first] + rest }
  }

  public enum Outcome: Hashable, Codable, Sendable {
    case running(tries: Int)
    /// The run's last sentence, and the sources it read.
    case finished(summary: String, sources: [String])
    case failed(String, tries: Int)
  }
}
