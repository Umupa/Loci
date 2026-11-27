import Foundation

/// Something the companion thinks the person should deal with, waiting at the top of the panel column until they
/// do, or until its deadline passes. It belongs to one home and is kept in the database. Where it sits on the deck
/// (`place`) and what its approval did (`execution`) are kept apart, so putting a done approval away and back
/// never makes it ask again.
public struct NextUp: Hashable, Codable, Sendable, Identifiable {
  public let id: EntityID
  public let home: Home
  /// The same thing again has the same key: once declined, it does not come back.
  public let key: String
  public let kind: Kind
  /// What happened, in a line.
  public let what: String
  /// Goes up each time anything the person sees of it changes: its words, where it is, what its approval did.
  /// Whatever the person does with it names the version they saw, and is refused for any other, so a Mac that
  /// saw an older card cannot undo what another did since.
  public let version: Int
  public let place: Place
  /// What an approval did; `.waiting` for a question.
  public let execution: Execution
  /// When it last came to the top; the newest is shown first.
  public let shownAt: Timestamp
  public let createdAt: Timestamp
  /// When it stops being worth acting on: past it the deck folds it away, unless its approval was written.
  public let deadline: Timestamp?
  /// What the person did with it that the daily review has not read yet.
  public let feedback: [Feedback]?

  /// Starting a card says it was worth telling; declining it, that it was noise.
  public struct Feedback: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable {
      case started, declined
    }

    public let kind: Kind
    public let at: Timestamp

    public init(_ kind: Kind, at: Timestamp) {
      self.kind = kind
      self.at = at
    }
  }

  public enum Kind: Hashable, Codable, Sendable {
    /// Starting it says `question` in the home's conversation, as the person.
    case ask(question: String)
    /// Something the companion would do for the person once they approve it, and can be undone.
    case approval(Approval)
  }

  /// Where the card is.
  public indirect enum Place: Hashable, Codable, Sendable {
    case new
    /// Kept where it is, without asking again.
    case kept
    /// Out of the way until then, when it comes back to the top.
    case later(until: Timestamp)
    case declined
    /// Its question is being said as `message`; it goes back to where it was if that message was never kept.
    case starting(from: Place, message: EntityID)
    case started
  }

  /// What an approval did, apart from where its card is.
  public enum Execution: Hashable, Codable, Sendable {
    case waiting
    /// Approved once: the calendars or lists of its name that macOS showed, for the person to confirm one.
    case choosing([ApprovalTarget])
    /// No calendar or list has the name it gave; approving again looks for the default one.
    case targetGone(String)
    /// Being written into `into`, by the one approval that claimed it; what is written carries `marker`, so it
    /// can be found again if the app stops before it is kept.
    case writing(marker: String, into: ApprovalTarget)
    case made(Approved)
    /// Being removed again.
    case undoing(Approved)

    /// Being written or removed: what became of it outside the app may not be known yet.
    public var isUnderWay: Bool {
      switch self {
      case .writing, .undoing: true
      case .waiting, .choosing, .targetGone, .made: false
      }
    }
  }

  public init(
    id: EntityID, home: Home, key: String, kind: Kind, what: String, version: Int = 1, place: Place = .new,
    execution: Execution = .waiting, shownAt: Timestamp, createdAt: Timestamp? = nil, deadline: Timestamp? = nil,
    feedback: [Feedback]? = nil
  ) {
    self.id = id
    self.home = home
    self.key = key
    self.kind = kind
    self.what = what
    self.version = version
    self.place = place
    self.execution = execution
    self.shownAt = shownAt
    self.createdAt = createdAt ?? shownAt
    self.deadline = deadline
    self.feedback = feedback
  }

  public func with(
    kind: Kind? = nil, what: String? = nil, version: Int? = nil, place: Place? = nil, execution: Execution? = nil,
    shownAt: Timestamp? = nil, deadline: Timestamp? = nil, adding given: Feedback? = nil
  ) -> NextUp {
    NextUp(
      id: id, home: home, key: key, kind: kind ?? self.kind, what: what ?? self.what, version: version ?? self.version,
      place: place ?? self.place, execution: execution ?? self.execution, shownAt: shownAt ?? self.shownAt,
      createdAt: createdAt, deadline: deadline ?? self.deadline,
      feedback: given.map { (feedback ?? []) + [$0] } ?? feedback)
  }

  /// The same card once a daily review read `read` of its feedback.
  public func reviewed(_ read: [Feedback]) -> NextUp {
    let left = (feedback ?? []).filter { !read.contains($0) }
    return NextUp(
      id: id, home: home, key: key, kind: kind, what: what, version: version, place: place, execution: execution,
      shownAt: shownAt, createdAt: createdAt, deadline: deadline, feedback: left.isEmpty ? nil : left)
  }

  public func isExpired(at now: Timestamp) -> Bool {
    deadline.map { $0 <= now } ?? false
  }

  /// Whether the deck shows it at `now`: not once its deadline passed, unless its approval was written.
  public func isShown(at now: Timestamp) -> Bool {
    if isExpired(at: now), isOpen { return false }
    return switch place {
    case .new, .kept: true
    case .later(let until): until <= now
    case .declined, .starting, .started: false
    }
  }

  /// The same card with new words or a new proposal, put again by the companion: it keeps the
  /// place the person gave it unless it was started. `nil` when the person declined it. An approval already
  /// done or under way keeps what it was; one waiting for the person to confirm where it goes asks again.
  public func putAgain(_ kind: Kind, what: String, at now: Timestamp, deadline: Timestamp? = nil) -> NextUp? {
    if place == .declined { return nil }
    if !isOpen { return self }
    let execution: Execution = kind == self.kind && !isTargetGone ? execution : .waiting
    switch place {
    case .kept: return with(kind: kind, what: what, execution: execution, deadline: deadline)
    case .later(let until) where until > now:
      return with(kind: kind, what: what, execution: execution, deadline: deadline)
    case .starting: return self
    case .new, .later, .started, .declined:
      return with(kind: kind, what: what, place: .new, execution: execution, shownAt: now, deadline: deadline)
    }
  }

  /// Whether nothing was written for it nor is being written.
  private var isOpen: Bool {
    switch execution {
    case .waiting, .choosing, .targetGone: true
    case .writing, .made, .undoing: false
    }
  }

  public var isTargetGone: Bool { if case .targetGone = execution { true } else { false } }

  /// The deck's order: new ones above kept ones, the latest to come up first.
  public static func deck(_ cards: [NextUp], at now: Timestamp) -> [NextUp] {
    cards.filter { $0.isShown(at: now) }.sorted { a, b in
      if (a.place == .kept) != (b.place == .kept) { return b.place == .kept }
      let first = a.cameUp
      let second = b.cameUp
      return first != second ? first > second : a.id.description > b.id.description
    }
  }

  private var cameUp: Timestamp {
    if case .later(let until) = place { max(until, shownAt) } else { shownAt }
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

  /// The calendar or list it goes to, by name; `nil` for the default one.
  public var target: String? {
    switch self {
    case .event(let event): event.calendar
    case .reminder(let reminder): reminder.list
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
  /// By name; `nil` for the default calendar. Which calendar of that name the app finds only once the person
  /// approves.
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
  /// By name; `nil` for the default list. Which list of that name the app finds only once the person approves.
  public let list: String?

  public init(title: String, due: Timestamp? = nil, list: String? = nil) {
    self.title = title
    self.due = due
    self.list = list
  }
}

/// A calendar or a list of reminders as macOS has it: its identifier, which stays, and its name and account,
/// which the card shows so two of one name can be told apart. Only the app finds these, never the companion.
public struct ApprovalTarget: Hashable, Codable, Sendable {
  public let id: String
  public let name: String
  /// The account it is in, such as iCloud.
  public let source: String

  public init(id: String, name: String, source: String) {
    self.id = id
    self.name = name
    self.source = source
  }
}

/// What an approval made and where, to remove it when the person undoes it: by its identifier, or, once a sync
/// lost that, by the marker it was written with.
public struct Approved: Hashable, Codable, Sendable {
  public let identifier: String
  public let marker: String
  public let into: ApprovalTarget

  public init(identifier: String, marker: String, into: ApprovalTarget) {
    self.identifier = identifier
    self.marker = marker
    self.into = into
  }
}
