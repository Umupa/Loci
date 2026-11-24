import Foundation

/// One thing to do in the background, kept in the inbox until a run has done it or given up on it.
public struct Event: Hashable, Codable, Sendable, Identifiable {
  public let id: EntityID
  public let source: Source
  /// When it came due; events due in the same minute share a run.
  public let due: Timestamp
  public let state: State

  public init(id: EntityID, source: Source, due: Timestamp, state: State = .waiting(nil)) {
    self.id = id
    self.source = source
    self.due = due
    self.state = state
  }

  /// The inbox keeps one event for each key: a timer that came due at a moment is raised once.
  public var key: String {
    switch source {
    case .schedule(let id): "schedule/\(id)/\(due)"
    case .followUp(let id): "follow-up/\(id)"
    case .panel(let name, let asked): "panel/\(name)/\(asked ? "asked/" : "")\(due)"
    case .review(let day): "review/\(day)"
    }
  }

  public func with(_ state: State) -> Event {
    Event(id: id, source: source, due: due, state: state)
  }

  /// What raised the event.
  public enum Source: Hashable, Codable, Sendable {
    case schedule(EntityID)
    case followUp(EntityID)
    /// A panel's refresh; `asked` when the person asked for it, which does not wait for the companion to be free.
    case panel(String, asked: Bool)
    case review(Day)

    /// The schedule it belongs to, for a schedule's or a panel's.
    public var schedule: ScheduleRef? {
      switch self {
      case .schedule(let id): .schedule(id)
      case .panel(let name, _): .panel(name)
      case .followUp, .review: nil
      }
    }
  }

  public enum State: Hashable, Codable, Sendable {
    /// Not started, or to be tried again after a run that failed or was cut short.
    case waiting(Retry?)
    case running(Run.ID, tries: Int)
    case done(Run.ID)
    case failed(Run.ID, reason: String)
    /// No longer wanted: its schedule or panel went away, or the person asked for the same sooner.
    case dropped

    public var isOpen: Bool {
      switch self {
      case .waiting, .running: true
      case .done, .failed, .dropped: false
      }
    }
  }

  /// A run to do again: the same run, so its record and its notes' tag stay the same.
  public struct Retry: Hashable, Codable, Sendable {
    public let run: Run.ID
    /// How many tries failed so far; a run cut short by quitting does not count.
    public let tries: Int
    /// Not to start before this.
    public let notBefore: Timestamp?

    public init(run: Run.ID, tries: Int, notBefore: Timestamp?) {
      self.run = run
      self.tries = tries
      self.notBefore = notBefore
    }
  }
}
