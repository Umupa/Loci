import Foundation
import LociModel
import Testing

@testable import LociTool

/// WK-S1, WK-S6: the companion sets schedules and follow-ups with `loci schedule` and `loci followup`.
struct TimerToolTests {
  static let zone = TimeZone(identifier: "Asia/Shanghai") ?? .gmt
  static let nine = Timestamp(millisecondsSince1970: 1_763_384_400_000)
  static let id = EntityID("019a8f40-1b2c-7d3e-8f40-5a6b7c8d9e0f") ?? EntityID()

  private static func json(_ value: some Encodable) -> Data {
    (try? Failure.encoding(value)) ?? Data()
  }

  private func tool(_ line: ScriptedLine, input: String = "") -> Tool {
    var tool = Tool(line: line, folder: URL(filePath: "/loci/agent/")) { _ in "" }
    tool.readInput = { Data(input.utf8) }
    tool.timeZone = Self.zone
    return tool
  }

  static func entry(_ ref: ScheduleRef, _ name: String, paused: Bool = false) throws -> ScheduleEntry {
    ScheduleEntry(
      ref: ref, name: name, title: "CubeSandbox 动静", every: .day(at: try #require(TimeOfDay("21:00"))),
      destination: .panel("sandbox-radar"), paused: paused, next: paused ? nil : nine, lastSummary: nil)
  }

  @Test func eachScheduleAndFollowUpVerbIsReadWithItsArguments() throws {
    let day = try #require(Day("2025-11-21"))
    #expect(try Request.parse(["schedule", "add", "sandbox-news"]) == (.schedule(.add("sandbox-news")), false))
    #expect(try Request.parse(["schedule", "list", "--json"]) == (.schedule(.list), true))
    #expect(try Request.parse(["schedule", "remove", "sandbox-news"]) == (.schedule(.remove("sandbox-news")), false))
    #expect(try Request.parse(["schedule", "change", "sandbox-news"]) == (.schedule(.change("sandbox-news")), false))
    #expect(
      try Request.parse(["followup", "2025-11-21", "10:00", "看看", "#244"])
        == (.followUp(.add(.at(day, TimeOfDay("10:00")), "看看 #244")), false))
    #expect(try Request.parse(["followup", "2025-11-21", "看看"]) == (.followUp(.add(.at(day, nil), "看看")), false))
    #expect(
      try Request.parse(["followup", "21:30", "再看"]) == (
        .followUp(.add(.next(try #require(TimeOfDay("21:30"))), "再看")), false
      ))
    #expect(try Request.parse(["followup", "in", "3h", "再看"]) == (.followUp(.add(.after(minutes: 180), "再看")), false))
    #expect(try Request.parse(["followup", "in", "2d", "再看"]) == (.followUp(.add(.after(minutes: 2880), "再看")), false))
    #expect(try Request.parse(["followup", "list"]) == (.followUp(.list), false))
    #expect(try Request.parse(["followup", "cancel", Self.id.description]) == (.followUp(.cancel(Self.id)), false))
  }

  @Test(arguments: [
    ["schedule"], ["schedule", "add"], ["schedule", "add", "News"], ["schedule", "drop", "x"],
    ["followup"], ["followup", "tomorrow", "x"], ["followup", "10:00"], ["followup", "in", "3", "x"],
    ["followup", "cancel", "x"],
  ])
  func aTimerCommandWrittenWrongSaysHowToWriteIt(_ words: [String]) {
    #expect(throws: UsageError.self) { try Request.parse(words) }
  }

  @Test func addingAScheduleSendsItsJSONAndSaysWhenItFirstRuns() async throws {
    let entry = try Self.entry(.schedule(Self.id), "sandbox-news")
    let line = ScriptedLine { _ in [.success(Self.json(entry))] }
    let input =
      #"{"title":"CubeSandbox 动静","follow":"看看","every":{"every":"day","at":"21:00"},"panel":"sandbox-radar"}"#

    let outcome = await tool(line, input: input).run(.schedule(.add("sandbox-news")), json: false)

    #expect(
      outcome
        == .worked(
          "Added sandbox-news, every day at 21:00, into the panel sandbox-radar. It first runs 2025-11-17 21:00."))
    let draft = ScheduleDraft(
      title: "CubeSandbox 动静", follow: "看看", every: entry.every, destination: .panel("sandbox-radar"))
    #expect(line.requests == [.command(name: AddSchedule.name, body: Self.json(AddSchedule("sandbox-news", draft)))])
  }

  @Test func changingAScheduleSendsOnlyWhatChangesAndSaysWhenItNextRuns() async throws {
    let entry = try Self.entry(.schedule(Self.id), "sandbox-news")
    let timers = Timers(schedules: [entry], followUps: [], next: nil)
    let line = ScriptedLine { request in
      if case .command(ListTimers.name, _) = request { return [.success(Self.json(timers))] }
      return [.success(Self.json(entry))]
    }

    let changed = await tool(line, input: #"{"every": {"every": "day", "at": "21:00"}, "panel": null}"#)
      .run(.schedule(.change("sandbox-news")), json: false)
    let missing = await tool(line, input: "{}").run(.schedule(.change("other")), json: false)

    #expect(
      changed
        == .worked(
          "Changed sandbox-news: every day at 21:00, into the panel sandbox-radar. It next runs 2025-11-17 21:00."))
    let change = ScheduleChange(every: entry.every, destination: .notes)
    let sent = line.requests.compactMap { request -> ChangeSchedule? in
      guard case .command(ChangeSchedule.name, let body) = request else { return nil }
      return try? JSONDecoder().decode(ChangeSchedule.self, from: body)
    }
    #expect(sent.map(\.schedule) == [.schedule(Self.id)] && sent.map(\.change) == [change])
    #expect(missing == .failed("There is no schedule other. Run `loci schedule list` to see them."))
  }

  @Test func aScheduleThatIsNotJSONIsNotSent() async {
    let line = ScriptedLine { _ in [] }

    let outcome = await tool(line, input: "every day").run(.schedule(.add("sandbox-news")), json: false)

    #expect(outcome.status == 1 && outcome.text.hasPrefix("The schedule was not added"))
    #expect(line.requests.isEmpty)
  }

  @Test func listingSaysHowOftenWhereAndWhenNextOrThatItIsPaused() async throws {
    let timers = Timers(
      schedules: [
        try Self.entry(.schedule(Self.id), "sandbox-news"),
        try Self.entry(.panel(PanelRef("radar")), "radar", paused: true),
      ], followUps: [], next: Self.nine)
    let line = ScriptedLine { _ in [.success(Self.json(timers))] }

    let outcome = await tool(line).run(.schedule(.list), json: false)

    #expect(
      outcome
        == .worked(
          "sandbox-news  CubeSandbox 动静, every day at 21:00, into the panel sandbox-radar; next 2025-11-17 21:00\n"
            + "radar (the panel's refresh)  CubeSandbox 动静, every day at 21:00, into the panel sandbox-radar; paused"))
  }

  @Test func removingAScheduleFindsItByName() async throws {
    let timers = Timers(schedules: [try Self.entry(.schedule(Self.id), "sandbox-news")], followUps: [], next: nil)
    let line = ScriptedLine { request in
      if case .command(ListTimers.name, _) = request { return [.success(Self.json(timers))] }
      return [.success(Self.json(Done()))]
    }

    let removed = await tool(line).run(.schedule(.remove("sandbox-news")), json: false)
    let missing = await tool(line).run(.schedule(.remove("other")), json: false)

    #expect(removed == .worked("Removed sandbox-news."))
    #expect(missing == .failed("There is no schedule other. Run `loci schedule list` to see them."))
    #expect(
      line.requests.contains(.command(name: RemoveSchedule.name, body: Self.json(RemoveSchedule(.schedule(Self.id))))))
  }

  @Test func settingAFollowUpSaysWhenItComesDue() async {
    let followUp = FollowUp(id: Self.id, due: Self.nine, what: "看看 #244", conversation: .main, createdAt: Self.nine)
    let line = ScriptedLine { _ in [.success(Self.json(followUp))] }

    let outcome = await tool(line).run(.followUp(.add(.after(minutes: 60), "看看 #244")), json: false)

    #expect(outcome == .worked("Set for 2025-11-17 21:00: 看看 #244  (\(Self.id))"))
  }
}
