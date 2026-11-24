import Foundation
import LociModel

/// The tools the calendar and reminders connectors offer: each only reads, and answers in plain lines.
public enum PersonalTools {
  public static func tools(for kind: PersonalKind) -> [MCPTool] {
    switch kind {
    case .events:
      [
        tool("calendars", "The calendars on this Mac, by name.", [:]),
        tool(
          "events",
          "The events between two days, earliest first. from and to are dates like 2026-11-24 (default: today and "
            + "the next 7 days); calendar narrows to one calendar by name; query keeps those whose title, place "
            + "or notes contain it.",
          ["from": "string", "to": "string", "calendar": "string", "query": "string"]),
      ]
    case .reminders:
      [
        tool("lists", "The reminder lists on this Mac, by name.", [:]),
        tool(
          "reminders",
          "The reminders still to do (or, with completed: true, the done ones), soonest due first; list narrows "
            + "to one list by name.",
          ["list": "string", "completed": "boolean"]),
      ]
    }
  }

  /// What the tool reads, as lines. Throws for a tool the kind does not have, or arguments it cannot read.
  public static func run(
    _ name: String, arguments: JSONValue, kind: PersonalKind, on data: any PersonalData, now: Date,
    calendar: Calendar
  ) async throws(ConnectError) -> String {
    switch (kind, name) {
    case (.events, "calendars"), (.reminders, "lists"):
      let names = kind == .events ? await data.calendars() : await data.reminderLists()
      return names.isEmpty ? "None." : names.map { "- \($0)" }.joined(separator: "\n")
    case (.events, "events"):
      let start = try day(arguments["from"]?.string, calendar: calendar) ?? calendar.startOfDay(for: now)
      let last =
        try day(arguments["to"]?.string, calendar: calendar) ?? calendar.date(byAdding: .day, value: 7, to: start)
      let end = calendar.date(byAdding: .day, value: 1, to: last ?? start) ?? start
      let query = arguments["query"]?.string
      let events = await data.events(from: start, to: end, calendars: arguments["calendar"]?.string.map { [$0] })
        .filter { event in
          guard let query, !query.isEmpty else { return true }
          return [event.title, event.location ?? "", event.notes ?? ""].contains {
            $0.localizedCaseInsensitiveContains(query)
          }
        }
      return events.isEmpty ? "No events." : events.map { line($0, calendar: calendar) }.joined(separator: "\n")
    case (.reminders, "reminders"):
      let reminders = await data.reminders(
        lists: arguments["list"]?.string.map { [$0] }, completed: arguments["completed"]?.bool ?? false
      ).sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
      return reminders.isEmpty
        ? "No reminders." : reminders.map { line($0, calendar: calendar) }.joined(separator: "\n")
    default:
      throw .server("there is no tool \(name)")
    }
  }

  private static func tool(_ name: String, _ description: String, _ properties: [String: String]) -> MCPTool {
    MCPTool(
      name: name, description: description,
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object(properties.mapValues { .object(["type": .string($0)]) }),
      ]), readOnly: true)
  }

  private static func day(_ text: String?, calendar: Calendar) throws(ConnectError) -> Date? {
    guard let text, !text.isEmpty else { return nil }
    let parts = text.prefix(10).split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3,
      let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    else { throw .server("\(text) is not a day like 2026-11-24") }
    return date
  }

  private static func line(_ event: CalendarEvent, calendar: Calendar) -> String {
    let when =
      event.allDay
      ? "\(stamp(event.start, calendar: calendar, time: false)) all day"
      : "\(stamp(event.start, calendar: calendar, time: true))–\(clock(event.end, calendar: calendar))"
    let place = event.location.map { " @ \($0)" } ?? ""
    return "- \(when)  \(event.title)\(place)  [\(event.calendar)]" + note(event.notes)
  }

  private static func line(_ reminder: Reminder, calendar: Calendar) -> String {
    let due = reminder.due.map { " (due \(stamp($0, calendar: calendar, time: true)))" } ?? ""
    return "- \(reminder.completed ? "[x]" : "[ ]") \(reminder.title)\(due)  [\(reminder.list)]" + note(reminder.notes)
  }

  private static func note(_ notes: String?) -> String {
    guard let first = notes?.split(separator: "\n").first, !first.isEmpty else { return "" }
    return "\n    " + String(first.prefix(200))
  }

  private static func stamp(_ date: Date, calendar: Calendar, time: Bool) -> String {
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    let day = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    return time ? "\(day) \(clock(date, calendar: calendar))" : day
  }

  private static func clock(_ date: Date, calendar: Calendar) -> String {
    let parts = calendar.dateComponents([.hour, .minute], from: date)
    return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
  }
}
