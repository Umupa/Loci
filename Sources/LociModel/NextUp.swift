import Foundation

/// Something the companion or a reminder condition thinks the person should deal with, waiting at the top of
/// the panel column until they do. It belongs to one home and is kept in the database.
public struct NextUp: Hashable, Codable, Sendable, Identifiable {
  public let id: EntityID
  public let home: Home
  /// The same thing again has the same key: once declined, it does not come back.
  public let key: String
  public let kind: Kind
  /// What happened, in a line.
  public let what: String
  public let state: State
  /// When it last came to the top; the newest is shown first.
  public let shownAt: Timestamp
  public let createdAt: Timestamp

  public enum Kind: Hashable, Codable, Sendable {
    /// Starting it says `question` in the home's conversation, as the person.
    case ask(question: String)
    /// Something the companion would do for the person once they approve it, and can be undone.
    case approval(Approval)
  }

  public enum State: Hashable, Codable, Sendable {
    case new
    /// Kept where it is, without asking again.
    case kept
    /// Out of the way until then, when it comes back to the top.
    case later(until: Timestamp)
    case declined
    case started
    /// An approval that was done; what it made is kept to undo it.
    case approved(Approved)
  }

  public init(
    id: EntityID, home: Home, key: String, kind: Kind, what: String, state: State = .new, shownAt: Timestamp,
    createdAt: Timestamp? = nil
  ) {
    self.id = id
    self.home = home
    self.key = key
    self.kind = kind
    self.what = what
    self.state = state
    self.shownAt = shownAt
    self.createdAt = createdAt ?? shownAt
  }

  public func with(
    kind: Kind? = nil, what: String? = nil, state: State? = nil, shownAt: Timestamp? = nil
  ) -> NextUp {
    NextUp(
      id: id, home: home, key: key, kind: kind ?? self.kind, what: what ?? self.what, state: state ?? self.state,
      shownAt: shownAt ?? self.shownAt, createdAt: createdAt)
  }

  /// Whether the deck shows it at `now`.
  public func isShown(at now: Timestamp) -> Bool {
    switch state {
    case .new, .kept, .approved: true
    case .later(let until): until <= now
    case .declined, .started: false
    }
  }

  /// The deck's order: new ones above kept ones, the latest to come up first.
  public static func deck(_ cards: [NextUp], at now: Timestamp) -> [NextUp] {
    cards.filter { $0.isShown(at: now) }.sorted { a, b in
      if a.isKept != b.isKept { return !a.isKept }
      let first = a.cameUp
      let second = b.cameUp
      return first != second ? first > second : a.id.description > b.id.description
    }
  }

  private var isKept: Bool { if case .kept = state { true } else { false } }

  private var cameUp: Timestamp {
    if case .later(let until) = state { max(until, shownAt) } else { shownAt }
  }

  /// The key of a line the companion wrote, when it gave none: the words without case or spacing.
  public static func key(of words: String) -> String {
    words.lowercased().filter { !$0.isWhitespace && !$0.isPunctuation }
  }
}

/// What an approval card may do. Paying, ordering, signing up and sending a message are none of these, and so
/// no card can ask for them.
public enum Approval: Hashable, Codable, Sendable {
  case event(EventDraft)
  case reminder(ReminderDraft)

  public var title: String {
    switch self {
    case .event(let event): event.title
    case .reminder(let reminder): reminder.title
    }
  }

  /// The same thing proposed twice has the same key.
  public var key: String {
    switch self {
    case .event(let event): "event/\(NextUp.key(of: event.title))/\(event.start)"
    case .reminder(let reminder): "reminder/\(NextUp.key(of: reminder.title))/\(reminder.due?.description ?? "")"
    }
  }
}

/// An event to put in the person's calendar.
public struct EventDraft: Hashable, Codable, Sendable {
  public let title: String
  public let start: Timestamp
  public let end: Timestamp
  public let allDay: Bool
  /// By name; `nil` for the default calendar.
  public let calendar: String?

  public init(title: String, start: Timestamp, end: Timestamp? = nil, allDay: Bool = false, calendar: String? = nil) {
    self.title = title
    self.start = start
    self.end = end ?? Timestamp(millisecondsSince1970: start.millisecondsSince1970 + 3_600_000)
    self.allDay = allDay
    self.calendar = calendar
  }
}

/// A reminder to add to the person's reminders.
public struct ReminderDraft: Hashable, Codable, Sendable {
  public let title: String
  public let due: Timestamp?
  /// By name; `nil` for the default list.
  public let list: String?

  public init(title: String, due: Timestamp? = nil, list: String? = nil) {
    self.title = title
    self.due = due
    self.list = list
  }
}

/// What an approval made, to remove it when the person undoes it.
public struct Approved: Hashable, Codable, Sendable {
  public let identifier: String

  public init(identifier: String) {
    self.identifier = identifier
  }
}
