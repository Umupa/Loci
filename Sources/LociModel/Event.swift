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
  /// A project's keys start with its folder, so the chat's keys stay as they always were.
  public var key: String {
    let key =
      switch source {
      case .schedule(let id, _): "schedule/\(id)/\(due)"
      case .followUp(let id, _): "follow-up/\(id)"
      case .panel(let name, let asked, _): "panel/\(name)/\(asked ? "asked/" : "")\(due)"
      case .review(let day, _): "review/\(day)"
      }
    return source.home.folder + key
  }

  public func with(_ state: State) -> Event {
    Event(id: id, source: source, due: due, state: state)
  }

  /// What raised the event, and the project it belongs to; `nil` for the chat's, as an event written before
  /// projects reads.
  public enum Source: Hashable, Codable, Sendable {
    case schedule(EntityID, project: Project.ID?)
    case followUp(EntityID, project: Project.ID?)
    /// A panel's refresh; `asked` when the person asked for it, which does not wait for the companion to be free.
    case panel(String, asked: Bool, project: Project.ID?)
    /// The daily review of the chat's memory, or of a project's.
    case review(Day, project: Project.ID?)

    public static func panel(_ panel: PanelRef, asked: Bool) -> Source {
      .panel(panel.name, asked: asked, project: panel.home.project)
    }

    /// Where its run works, and where what it finds is told.
    public var home: Home {
      switch self {
      case .schedule(_, let project), .followUp(_, let project), .panel(_, _, let project), .review(_, let project):
        Home(project)
      }
    }

    /// The panel it refreshes, for a panel's.
    public var panel: PanelRef? {
      if case .panel(let name, _, let project) = self { PanelRef(name, in: Home(project)) } else { nil }
    }

    /// The schedule it belongs to, for a schedule's or a panel's.
    public var schedule: ScheduleRef? {
      switch self {
      case .schedule(let id, _): .schedule(id)
      case .panel(let name, _, let project): .panel(name, project: project)
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
