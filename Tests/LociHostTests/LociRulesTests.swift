import Foundation
import LociModel
import LociStore
import Testing

@testable import LociHost

struct TurnContextTests {
  static let context = TurnContext(
    now: TestWorld.instant, timeZone: TestWorld.timeZone, conversation: .item(TestWorld().nextID()),
    happenings: (1...25).map { "- fact \($0)" }, open: nil,
    files: [
      .init(path: "MEMORY.md", text: "# Memory\n- a\n", keep: nil),
      .init(path: "notes/2025-11-17.md", text: String(repeating: "x", count: 50), keep: 10),
    ])

  @Test func theNewestHappeningsAreListedAndTheRestCounted() {
    let text = Self.context.prefix(shown: [:]).text

    #expect(text.contains("- fact 25") && text.contains("- fact 6\n"))
    #expect(!text.contains("- fact 5\n"))
    #expect(text.contains("…and 5 earlier."))
  }

  @Test func aFileShownBeforeIsLeftOutUntilItChanges() {
    let first = Self.context.prefix(shown: [:])
    let again = Self.context.prefix(shown: first.shown)

    #expect(first.text.contains("MEMORY.md:\n# Memory\n- a"))
    #expect(!again.text.contains("MEMORY.md:"))
    #expect(again.shown == first.shown)
  }

  @Test func aLongFileKeepsItsEndAndSaysWhereTheRestIs() {
    let text = Self.context.prefix(shown: [:]).text

    #expect(text.contains("notes/2025-11-17.md:\n…xxxxxxxxxx\n(Earlier notes are in notes/2025-11-17.md"))
  }

  @Test func theTimeOfDayHasAName() {
    #expect(TurnContext.part(of: TimeOfDay(hour: 9, minute: 0)!) == "morning")
    #expect(TurnContext.part(of: TimeOfDay(hour: 14, minute: 0)!) == "afternoon")
    #expect(TurnContext.part(of: TimeOfDay(hour: 20, minute: 0)!) == "evening")
    #expect(TurnContext.part(of: TimeOfDay(hour: 1, minute: 0)!) == "late night")
  }
}

struct SessionRotationTests {
  static let runtime = Runtime(provider: .pi)
  static let session = SessionRecord(
    id: TestWorld().nextID(), owner: .conversation(.main), runtime: runtime, instructions: "a",
    startedAt: TestWorld.instant)

  static func reason(_ wear: SessionRotation.Wear = .init(), runtime: Runtime = runtime, instructions: String = "a")
    -> SessionRotation.Reason?
  {
    SessionRotation.reason(
      current: session, startedOver: false, wear: wear, runtime: runtime, instructions: instructions)
  }

  @Test func aSessionGoesOnUntilSomethingChanges() {
    #expect(Self.reason() == nil)
    #expect(Self.reason(runtime: Runtime(provider: .pi, model: "m")) == .runtimeChanged)
    #expect(Self.reason(instructions: "b") == .instructionsChanged)
  }

  @Test func withoutASessionTheReasonSaysWhetherThePersonStartedOver() {
    let first = SessionRotation.reason(
      current: nil, startedOver: false, wear: .init(), runtime: Self.runtime, instructions: "a")
    let over = SessionRotation.reason(
      current: nil, startedOver: true, wear: .init(), runtime: Self.runtime, instructions: "a")

    #expect(first == .first && over == .startedOver)
    #expect(!SessionRotation.Reason.first.carriesOver && !SessionRotation.Reason.startedOver.carriesOver)
    #expect(SessionRotation.Reason.full.carriesOver && SessionRotation.Reason.runtimeChanged.carriesOver)
  }

  @Test func fullIsJudgedByTheReportThenByTheEstimate() {
    #expect(Self.reason(.init(usage: ContextUsage(used: 149_999, window: 200_000))) == nil)
    #expect(Self.reason(.init(usage: ContextUsage(used: 150_000, window: 200_000))) == .full)
    #expect(Self.reason(.init(usage: ContextUsage(used: 150_000, window: nil))) == .full)
    #expect(Self.reason(.init(usage: ContextUsage(used: 100_000, window: nil), characters: 900_000)) == nil)
    #expect(Self.reason(.init(characters: 449_997)) == nil)
    #expect(Self.reason(.init(characters: 450_000)) == .full)
    #expect(Self.reason(.init(compacted: true)) == .full)
  }
}

struct DailyReviewTests {
  static func due(
    at time: String, daysLater: Int = 0, working: Bool = false, lastSaid: Int64? = nil,
    reviewed: Set<String> = [], active: Set<String> = ["2025-11-17", "2025-11-18"]
  ) -> Day? {
    let world = TestWorld()
    world.set(to: time, daysLater: daysLater)
    let now = world.now
    return DailyReview.due(
      .init(
        now: now, timeZone: TestWorld.timeZone, working: working,
        lastSaid: {
          lastSaid.map { Timestamp(millisecondsSince1970: now.millisecondsSince1970 - $0 * 60_000) }
        },
        reviewed: { reviewed.contains($0.description) }, active: { active.contains($0.description) }))
  }

  @Test func theDayIsDueAfterElevenOnceItIsQuiet() {
    #expect(Self.due(at: "22:59") == nil)
    #expect(Self.due(at: "23:00") == Day("2025-11-17"))
    #expect(Self.due(at: "23:30", lastSaid: 9) == nil)
    #expect(Self.due(at: "23:30", lastSaid: 10) == Day("2025-11-17"))
    #expect(Self.due(at: "23:30", working: true) == nil)
  }

  @Test func aDayIsLookedBackOnOnceAndOnlyWhenSomethingHappened() {
    #expect(Self.due(at: "23:30", reviewed: ["2025-11-17"]) == nil)
    #expect(Self.due(at: "23:30", active: []) == nil)
  }

  @Test func yesterdayIsCaughtUpFirst() {
    #expect(Self.due(at: "08:00", daysLater: 1) == Day("2025-11-17"))
    #expect(Self.due(at: "23:30", daysLater: 1, reviewed: ["2025-11-17"]) == Day("2025-11-18"))
    #expect(Self.due(at: "08:00", daysLater: 1, active: ["2025-11-18"]) == nil)
  }
}

struct RecapTests {
  static func message(_ body: Message.Body) -> Message {
    Message(id: TestWorld().nextID(), at: TestWorld.instant, body: body)
  }

  @Test func aRecapHoldsTheWordsSaidSinceTheLastStartOver() throws {
    let stored = [
      Self.message(.prompt(Prompt(text: "old", purpose: .chat))), Self.message(.startedOver),
      Self.message(.prompt(Prompt(text: "新的", purpose: .chat))), Self.message(.thinking("hm")),
      Self.message(.reply("好")),
    ]

    let recap = try #require(Recap.of(stored))

    #expect(recap.contains("Person: 新的\n\nCompanion: 好"))
    #expect(!recap.contains("old") && !recap.contains("hm"))
  }

  @Test func aRecapKeepsTheLatestWordsWithinItsLimits() throws {
    let stored = (0..<50).map { Self.message(.reply("reply \($0)")) }

    let recap = try #require(Recap.of(stored))

    #expect(recap.contains("reply 49") && recap.contains("reply 30"))
    #expect(!recap.contains("reply 29"))
    #expect(Recap.of([Self.message(.startedOver)]) == nil)
  }
}
