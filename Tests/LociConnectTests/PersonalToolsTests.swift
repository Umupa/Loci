import Foundation
import LociModel
import Synchronization
import Testing

@testable import LociConnect

/// CN-S13: the calendar and reminders connectors read through their own tools, in plain lines.
struct PersonalToolsTests {
  static var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .gmt
    return calendar
  }

  static func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute)) ?? .distantPast
  }

  private func run(
    _ tool: String, _ arguments: JSONValue = .object([:]), kind: PersonalKind = .events,
    on data: SamplePersonalData = SamplePersonalData()
  ) async throws -> String {
    try await PersonalTools.run(
      tool, arguments: arguments, kind: kind, on: data, now: Self.at(24, 15), calendar: Self.calendar)
  }

  @Test func everyToolOnlyReadsAndSaysWhatItTakes() {
    let tools = PersonalTools.tools(for: .events) + PersonalTools.tools(for: .reminders)
    #expect(tools.map(\.name) == ["calendars", "events", "lists", "reminders"])
    #expect(tools.allSatisfy { $0.readOnly == true })
    #expect(tools[1].inputSchema["properties"]?["from"]?["type"]?.string == "string")
  }

  @Test func eventsDefaultToTheNextWeekAndReadAsLines() async throws {
    let data = SamplePersonalData()
    let text = try await run("events", on: data)
    #expect(
      text
        == "- 2026-11-24 19:00–20:00  组会 @ 3 楼会议室  [工作]\n    带上调度的图\n"
        + "- 2026-11-28 all day  爬山  [家庭]")
    #expect(data.asked.last?.0 == Self.at(24, 0))
    #expect(data.asked.last?.1 == Self.calendar.date(byAdding: .day, value: 8, to: Self.at(24, 0)))
  }

  @Test func eventsCanBeNarrowedByDaysCalendarAndWords() async throws {
    let text = try await run(
      "events", .object(["from": .string("2026-11-28"), "to": .string("2026-11-28"), "query": .string("爬山")]))
    #expect(text == "- 2026-11-28 all day  爬山  [家庭]")
    await #expect(throws: ConnectError.self) { try await run("events", .object(["from": .string("next week")])) }
  }

  @Test func remindersStillToDoComeSoonestFirst() async throws {
    let text = try await run("reminders", kind: .reminders)
    #expect(text == "- [ ] 交房租 (due 2026-11-25 09:00)  [生活]\n- [ ] 读 E2B 论文  [学习]")
    #expect(try await run("lists", kind: .reminders) == "- 生活\n- 学习")
  }

  @Test func aToolTheKindDoesNotHaveIsRefused() async {
    await #expect(throws: ConnectError.self) { try await run("reminders", kind: .events) }
    await #expect(throws: ConnectError.self) { try await run("create_event") }
  }
}

/// A Mac with a few events and reminders, which remembers the intervals it was asked for.
final class SamplePersonalData: PersonalData {
  private let intervals = Mutex<[(Date, Date)]>([])

  var asked: [(Date, Date)] { intervals.withLock { $0 } }

  func access(to kind: PersonalKind) async -> PersonalAccess { .granted }
  func requestAccess(to kind: PersonalKind) async -> Bool { true }
  func calendars() async -> [String] { ["工作", "家庭"] }

  func events(from start: Date, to end: Date, calendars: [String]?) async -> [CalendarEvent] {
    intervals.withLock { $0.append((start, end)) }
    let all = [
      CalendarEvent(
        title: "组会", start: PersonalToolsTests.at(24, 19), end: PersonalToolsTests.at(24, 20), calendar: "工作",
        location: "3 楼会议室", notes: "带上调度的图\n第二行不显示"),
      CalendarEvent(
        title: "爬山", start: PersonalToolsTests.at(28, 0), end: PersonalToolsTests.at(29, 0), allDay: true,
        calendar: "家庭"),
    ]
    return all.filter { $0.start >= start && $0.start < end && (calendars?.contains($0.calendar) ?? true) }
  }

  func reminderLists() async -> [String] { ["生活", "学习"] }

  func reminders(lists: [String]?, completed: Bool) async -> [Reminder] {
    [
      Reminder(title: "读 E2B 论文", list: "学习"),
      Reminder(title: "交房租", list: "生活", due: PersonalToolsTests.at(25, 9)),
    ].filter { _ in !completed }
  }
}
