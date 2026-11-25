import EventKit
import Foundation
import LociModel

/// Puts an event in the person's calendar or a reminder in their reminders, and takes it out again. Only an
/// approval card the person approved gets here; the companion's connector tools only read.
public protocol PersonalWrites: Sendable {
  /// Asks macOS when it has not been asked; whether writing is allowed now.
  func allow(_ kind: PersonalKind) async -> Bool
  /// What it made, to remove it when the approval is undone.
  func make(_ approval: Approval) async throws(ConnectError) -> String
  func remove(_ identifier: String, of kind: PersonalKind) async throws(ConnectError)
}

extension Approval {
  public var personalKind: PersonalKind {
    switch self {
    case .event: .events
    case .reminder: .reminders
    }
  }
}

/// The calendars and reminders of this Mac through EventKit, written to only once the person approved.
public actor EventKitWrites: PersonalWrites {
  private let store = EKEventStore()
  private let reading = EventKitData()

  public init() {}

  public func allow(_ kind: PersonalKind) async -> Bool {
    switch await reading.access(to: kind) {
    case .granted: return true
    case .denied: return false
    case .undetermined: return await reading.requestAccess(to: kind)
    }
  }

  public func make(_ approval: Approval) throws(ConnectError) -> String {
    do {
      switch approval {
      case .event(let draft):
        let event = EKEvent(eventStore: store)
        event.title = draft.title
        event.startDate = draft.start.date
        event.endDate = draft.end.date
        event.isAllDay = draft.allDay
        event.calendar =
          draft.calendar.flatMap { name in store.calendars(for: .event).first { $0.title == name } }
          ?? store.defaultCalendarForNewEvents
        try store.save(event, span: .thisEvent, commit: true)
        return event.calendarItemIdentifier
      case .reminder(let draft):
        let reminder = EKReminder(eventStore: store)
        reminder.title = draft.title
        reminder.dueDateComponents = draft.due.map {
          Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: $0.date)
        }
        reminder.calendar =
          draft.list.flatMap { name in store.calendars(for: .reminder).first { $0.title == name } }
          ?? store.defaultCalendarForNewReminders()
        try store.save(reminder, commit: true)
        return reminder.calendarItemIdentifier
      }
    } catch {
      throw .server(error.localizedDescription)
    }
  }

  public func remove(_ identifier: String, of kind: PersonalKind) throws(ConnectError) {
    guard let item = store.calendarItem(withIdentifier: identifier) else { return }
    do {
      switch (kind, item) {
      case (.events, let event as EKEvent): try store.remove(event, span: .thisEvent, commit: true)
      case (.reminders, let reminder as EKReminder): try store.remove(reminder, commit: true)
      default: return
      }
    } catch {
      throw .server(error.localizedDescription)
    }
  }
}

/// A Mac where nothing may be written, as in previews and most tests.
public struct NoPersonalWrites: PersonalWrites {
  public init() {}
  public func allow(_ kind: PersonalKind) async -> Bool { false }
  public func make(_ approval: Approval) async throws(ConnectError) -> String { throw .server("not allowed") }
  public func remove(_ identifier: String, of kind: PersonalKind) async throws(ConnectError) {}
}
