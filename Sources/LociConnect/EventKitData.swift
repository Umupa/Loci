import EventKit
import Foundation

/// Reads the calendars and reminders of this Mac through EventKit; writing is `EventKitWrites`'.
public actor EventKitData: PersonalData {
  private let store = EKEventStore()

  public init() {}

  public func access(to kind: PersonalKind) -> PersonalAccess {
    switch EKEventStore.authorizationStatus(for: Self.type(kind)) {
    case .fullAccess: .granted
    case .notDetermined: .undetermined
    case .denied, .restricted, .writeOnly: .denied
    @unknown default: .denied
    }
  }

  public func requestAccess(to kind: PersonalKind) async -> Bool {
    do {
      switch kind {
      case .events: return try await store.requestFullAccessToEvents()
      case .reminders: return try await store.requestFullAccessToReminders()
      }
    } catch {
      return false
    }
  }

  public func calendars() -> [String] {
    store.calendars(for: .event).map(\.title)
  }

  public func events(from start: Date, to end: Date, calendars names: [String]?) -> [CalendarEvent] {
    let chosen = names.map { names in store.calendars(for: .event).filter { names.contains($0.title) } }
    let predicate = store.predicateForEvents(withStart: start, end: end, calendars: chosen)
    return store.events(matching: predicate).sorted { $0.startDate < $1.startDate }.map { event in
      CalendarEvent(
        title: event.title ?? "", start: event.startDate, end: event.endDate, allDay: event.isAllDay,
        calendar: event.calendar?.title ?? "", location: event.location, notes: event.notes)
    }
  }

  public func reminderLists() -> [String] {
    store.calendars(for: .reminder).map(\.title)
  }

  public func reminders(lists names: [String]?, completed: Bool) async -> [Reminder] {
    let chosen = names.map { names in store.calendars(for: .reminder).filter { names.contains($0.title) } }
    let predicate =
      completed
      ? store.predicateForCompletedReminders(withCompletionDateStarting: nil, ending: nil, calendars: chosen)
      : store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: chosen)
    let found: [Reminder] = await withCheckedContinuation { done in
      store.fetchReminders(matching: predicate) { reminders in
        done.resume(
          returning: (reminders ?? []).map { reminder in
            Reminder(
              title: reminder.title ?? "", list: reminder.calendar?.title ?? "",
              due: reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) },
              completed: reminder.isCompleted, notes: reminder.notes)
          })
      }
    }
    return found
  }

  private static func type(_ kind: PersonalKind) -> EKEntityType {
    switch kind {
    case .events: .event
    case .reminders: .reminder
    }
  }
}
