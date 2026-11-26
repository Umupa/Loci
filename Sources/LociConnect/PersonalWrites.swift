import EventKit
import Foundation
import LociModel

/// Puts an event in the person's calendar or a reminder in their reminders, and takes it out again. Only an
/// approval card the person approved gets here; the companion's connector tools only read.
public protocol PersonalWrites: Sendable {
  /// Asks macOS when it has not been asked; whether writing is allowed now.
  func allow(_ kind: PersonalKind) async -> Bool
  /// The calendars or lists called `name` that can be written to, or the default one for `nil`; none when there
  /// is none or they cannot be read.
  func targets(named name: String?, of kind: PersonalKind) async -> [ApprovalTarget]
  /// Writes into `target`, and gives what it made, to remove it when the approval is undone; it carries
  /// `marker`, for `find`. A target that is not there is `targetGone`, never another in its place.
  func make(_ approval: Approval, in target: ApprovalTarget, marker: String) async throws(WriteFailure) -> String
  /// Whether `make` made something with `marker` in `target`.
  func find(_ marker: String, for approval: Approval, in target: ApprovalTarget) async -> Lookup
  /// Removes what `make` made, found by its identifier or else by its marker; done when it is already gone,
  /// failed when that cannot be told.
  func remove(_ made: Approved, for approval: Approval) async throws(WriteFailure)
}

/// What looking for something written found.
public enum Lookup: Hashable, Sendable {
  case found(String)
  /// Looked, and it is not there.
  case absent
  /// Could not look: no access, or macOS did not answer.
  case unknown
}

/// Why nothing was written.
public enum WriteFailure: Error, Hashable, Sendable {
  case targetGone(String)
  case failed(String)
}

extension Approval {
  public var personalKind: PersonalKind {
    switch self {
    case .event: .events
    case .reminder: .reminders
    }
  }
}

/// Whether the app may write to the calendar or the reminders. macOS is asked once; what it allowed stays
/// allowed for as long as the app runs, since for an app signed only for this Mac macOS may let it in without
/// asking the person and still say afterwards that it was never asked.
actor WriteAccess {
  private let status: @Sendable (PersonalKind) async -> PersonalAccess
  private let request: @Sendable (PersonalKind) async -> Bool
  private var allowed: Set<PersonalKind> = []

  init(
    status: @escaping @Sendable (PersonalKind) async -> PersonalAccess,
    request: @escaping @Sendable (PersonalKind) async -> Bool
  ) {
    self.status = status
    self.request = request
  }

  /// Asks macOS when it was never asked; whether writing is allowed now.
  func allow(_ kind: PersonalKind) async -> Bool {
    if allowed.contains(kind) { return true }
    let yes =
      switch await status(kind) {
      case .granted: true
      case .denied: false
      case .undetermined: await request(kind)
      }
    if yes { allowed.insert(kind) }
    return yes
  }

  /// Whether writing is allowed, without asking anyone: what macOS says is granted, or allowed earlier in this run.
  func isAllowed(_ kind: PersonalKind) async -> Bool {
    if allowed.contains(kind) { return true }
    guard await status(kind) == .granted else { return false }
    allowed.insert(kind)
    return true
  }
}

/// The calendars and reminders of this Mac through EventKit, written to only once the person approved.
public actor EventKitWrites: PersonalWrites {
  private let store = EKEventStore()
  private let access: WriteAccess
  /// What this store was let at since it was made; a store made before access was given sees no calendars
  /// until it is reset.
  private var opened: Set<PersonalKind> = []

  public init() {
    let reading = EventKitData()
    access = WriteAccess(
      status: { await reading.access(to: $0) }, request: { await reading.requestAccess(to: $0) })
  }

  public func allow(_ kind: PersonalKind) async -> Bool {
    guard await access.allow(kind) else { return false }
    open(kind)
    return true
  }

  /// Whether the store may be used now, without asking the person.
  private func isOpen(_ kind: PersonalKind) async -> Bool {
    guard await access.isAllowed(kind) else { return false }
    open(kind)
    return true
  }

  private func open(_ kind: PersonalKind) {
    guard !opened.contains(kind) else { return }
    store.reset()
    opened.insert(kind)
  }

  public func targets(named name: String?, of kind: PersonalKind) async -> [ApprovalTarget] {
    guard await allow(kind) else { return [] }
    let calendars: [EKCalendar] =
      if let name {
        store.calendars(for: Self.type(kind)).filter { $0.title == name && $0.allowsContentModifications }
      } else {
        [kind == .events ? store.defaultCalendarForNewEvents : store.defaultCalendarForNewReminders()]
          .compactMap(\.self)
      }
    return calendars.map {
      ApprovalTarget(id: $0.calendarIdentifier, name: $0.title, source: $0.source?.title ?? "")
    }
  }

  public func make(_ approval: Approval, in target: ApprovalTarget, marker: String) async throws(WriteFailure)
    -> String
  {
    guard await allow(approval.personalKind) else { throw .failed("no access") }
    guard let calendar = store.calendar(withIdentifier: target.id) else { throw .targetGone(target.name) }
    let url = Self.url(marker)
    do {
      switch approval {
      case .event(let draft):
        let event = EKEvent(eventStore: store)
        event.title = draft.title
        event.startDate = draft.start.date
        event.endDate = draft.end.date
        event.isAllDay = draft.allDay
        event.url = url
        event.calendar = calendar
        try store.save(event, span: .thisEvent, commit: true)
        return event.calendarItemIdentifier
      case .reminder(let draft):
        let reminder = EKReminder(eventStore: store)
        reminder.title = draft.title
        reminder.dueDateComponents = draft.due.map {
          Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: $0.date)
        }
        reminder.url = url
        reminder.calendar = calendar
        try store.save(reminder, commit: true)
        return reminder.calendarItemIdentifier
      }
    } catch {
      throw .failed(error.localizedDescription)
    }
  }

  public func find(_ marker: String, for approval: Approval, in target: ApprovalTarget) async -> Lookup {
    guard await isOpen(approval.personalKind) else { return .unknown }
    guard let calendar = store.calendar(withIdentifier: target.id) else { return .absent }
    let url = Self.url(marker)
    switch approval {
    case .event(let draft):
      let day: TimeInterval = 86_400
      let predicate = store.predicateForEvents(
        withStart: draft.start.date.addingTimeInterval(-day), end: draft.end.date.addingTimeInterval(day),
        calendars: [calendar])
      return store.events(matching: predicate).first { $0.url == url }.map { .found($0.calendarItemIdentifier) }
        ?? .absent
    case .reminder:
      let predicate = store.predicateForReminders(in: [calendar])
      let found: [String]? = await withCheckedContinuation { done in
        store.fetchReminders(matching: predicate) { reminders in
          done.resume(returning: reminders.map { $0.filter { $0.url == url }.map(\.calendarItemIdentifier) })
        }
      }
      guard let found else { return .unknown }
      return found.first.map(Lookup.found) ?? .absent
    }
  }

  public func remove(_ made: Approved, for approval: Approval) async throws(WriteFailure) {
    let kind = approval.personalKind
    guard await isOpen(kind) else { throw .failed("no access") }
    var found = store.calendarItem(withIdentifier: made.identifier)
    if found == nil {
      switch await find(made.marker, for: approval, in: made.into) {
      case .found(let identifier): found = store.calendarItem(withIdentifier: identifier)
      case .absent: return
      case .unknown: throw .failed("could not look for it")
      }
    }
    guard let item = found else { throw .failed("could not open it") }
    do {
      switch (kind, item) {
      case (.events, let event as EKEvent): try store.remove(event, span: .thisEvent, commit: true)
      case (.reminders, let reminder as EKReminder): try store.remove(reminder, commit: true)
      default: return
      }
    } catch {
      throw .failed(error.localizedDescription)
    }
  }

  private static func type(_ kind: PersonalKind) -> EKEntityType {
    switch kind {
    case .events: .event
    case .reminders: .reminder
    }
  }

  private static func url(_ marker: String) -> URL? {
    URL(string: "loci://next-up/\(marker)")
  }
}

/// A Mac where nothing may be written, as in previews and most tests.
public struct NoPersonalWrites: PersonalWrites {
  public init() {}
  public func allow(_ kind: PersonalKind) async -> Bool { false }
  public func targets(named name: String?, of kind: PersonalKind) async -> [ApprovalTarget] { [] }
  public func make(_ approval: Approval, in target: ApprovalTarget, marker: String) async throws(WriteFailure)
    -> String
  {
    throw .failed("not allowed")
  }
  public func find(_ marker: String, for approval: Approval, in target: ApprovalTarget) async -> Lookup { .unknown }
  public func remove(_ made: Approved, for approval: Approval) async throws(WriteFailure) {
    throw .failed("not allowed")
  }
}
