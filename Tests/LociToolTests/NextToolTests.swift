import Foundation
import LociModel
import Testing

@testable import LociTool

/// NX-S2, NX-S5, NX-S6, NX-S7: the companion puts cards, reminder conditions and approval cards with
/// `loci next`, and has no way to propose paying, ordering, signing up or sending a message.
struct NextToolTests {
  static let zone = TimeZone(identifier: "Asia/Shanghai") ?? .gmt
  static let id = EntityID("019a8f40-1b2c-7d3e-8f40-5a6b7c8d9e0f") ?? EntityID()

  private static func json(_ value: some Encodable) -> Data {
    (try? Failure.encoding(value)) ?? Data()
  }

  private func tool(_ line: ScriptedLine) -> Tool {
    var tool = Tool(line: line, folder: URL(filePath: "/loci/agent/")) { _ in "" }
    tool.timeZone = Self.zone
    return tool
  }

  @Test func eachVerbIsReadWithItsArguments() throws {
    #expect(
      try Request.parse(["next", "add", "费城半导体跌", "8%", "--ask", "这对我意味着什么"])
        == (.next(.add(what: "费城半导体跌 8%", question: "这对我意味着什么", key: nil)), false))
    #expect(
      try Request.parse(["next", "when", "prem.513100.premium", "<", "0.03", "--say", "溢价 {value}", "--ask", "买吗"])
        == (.next(.when(SourceField("prem.513100.premium")!, .below, 0.03, say: "溢价 {value}", question: "买吗")), false))
    #expect(try Request.parse(["next", "conditions"]) == (.next(.conditions), false))
    #expect(try Request.parse(["next", "unwhen", Self.id.description]) == (.next(.unwhen(Self.id)), false))
    let day = try #require(Day("2026-11-30"))
    #expect(
      try Request.parse(["next", "propose", "event", "投资复盘", "--at", "2026-11-30", "20:00", "--calendar", "家庭"])
        == (
          .next(.propose(.event(title: "投资复盘", at: day, TimeOfDay("20:00"), until: nil, calendar: "家庭", why: nil))),
          false
        ))
    #expect(
      try Request.parse(["next", "propose", "reminder", "交房租"])
        == (.next(.propose(.reminder(title: "交房租", at: nil, nil, list: nil, why: nil))), false))
  }

  @Test(arguments: [
    ["next"], ["next", "add", "x"], ["next", "add", "--ask", "y"], ["next", "add", "x", "--ask", "y", "--when", "z"],
    ["next", "when", "prem.513100.premium", "<", "0.03", "--say", "x"], ["next", "when", "prem", "<", "0.03"],
    ["next", "when", "prem.513100.premium", "≈", "0.03", "--say", "x", "--ask", "y"],
    ["next", "propose", "event", "复盘"], ["next", "propose", "event", "复盘", "--at", "明天"],
    ["next", "unwhen", "x"],
  ])
  func aNextCommandWrittenWrongSaysHowToWriteIt(_ words: [String]) {
    #expect(throws: UsageError.self) { try Request.parse(words) }
  }

  @Test(arguments: ["payment", "order", "signup", "message"])
  func onlyAnEventOrAReminderCanBeProposed(_ kind: String) {
    #expect(throws: UsageError(NextRequest.onlyTwo)) { try Request.parse(["next", "propose", kind, "x"]) }
  }

  @Test func anEventIsReadInThePersonsTimeZoneAndOneWithoutATimeIsAllDay() throws {
    let day = try #require(Day("2025-11-30"))
    let (timed, _) = NextRequest.Proposal.event(
      title: "复盘", at: day, TimeOfDay("20:00"), until: TimeOfDay("21:30"), calendar: nil, why: nil
    ).approval(in: Self.zone)
    let (allDay, _) = NextRequest.Proposal.event(title: "休假", at: day, nil, until: nil, calendar: nil, why: nil)
      .approval(in: Self.zone)

    let start = Timestamp(millisecondsSince1970: 1_764_504_000_000)
    #expect(
      timed == .event(EventDraft(title: "复盘", start: start, end: Timestamp(millisecondsSince1970: 1_764_509_400_000))))
    #expect(
      allDay
        == .event(
          EventDraft(
            title: "休假", start: Timestamp(millisecondsSince1970: 1_764_432_000_000),
            end: Timestamp(millisecondsSince1970: 1_764_518_400_000), allDay: true)))
  }

  @Test func addingACardSaysItIsOnTheDeck() async {
    let card = NextUp(
      id: Self.id, home: .chat, key: "k", kind: .ask(question: "买吗"), what: "溢价回到 2.8%",
      shownAt: Timestamp(millisecondsSince1970: 0))
    let line = ScriptedLine { _ in [.success(Self.json(card))] }

    let outcome = await tool(line).run(.next(.add(what: "溢价回到 2.8%", question: "买吗", key: nil)), json: false)

    #expect(outcome == .worked("On the deck: 溢价回到 2.8%"))
    #expect(line.requests == [.command(name: AddNextUp.name, body: Self.json(AddNextUp("溢价回到 2.8%", asking: "买吗")))])
  }
}
