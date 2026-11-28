import Foundation
import Testing

@testable import LociModel

/// Everything that crosses the host protocol must survive the trip a remote host will give it.
struct HostCodingTests {
  static func roundTrips<Value: Codable>(_ value: Value) throws -> Bool {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let once = try encoder.encode(value)
    return try encoder.encode(JSONDecoder().decode(Value.self, from: once)) == once
  }

  /// For values whose encoding has no fixed order, such as sets.
  static func decodesEqual<Value: Codable & Equatable>(_ value: Value) throws -> Bool {
    try JSONDecoder().decode(Value.self, from: JSONEncoder().encode(value)) == value
  }

  static let day = Day("2026-11-18")!

  @Test func everyCommandSurvivesJSON() throws {
    let passage = Passage(locator: .item(Fixture.item, .quote(try TextQuote("打分"))), excerpt: "打分")
    #expect(try Self.roundTrips(AddTextItem(fileName: "a.md", text: "# A\n")))
    #expect(try Self.roundTrips(DeleteItems([Fixture.item])))
    #expect(try Self.roundTrips(ListItems()))
    #expect(try Self.roundTrips(ReadItemText(item: Fixture.item)))
    #expect(try Self.roundTrips(Search(text: "调度", limit: 10)))
    #expect(try Self.roundTrips(ReadReadingState(content: .item(Fixture.item))))
    #expect(
      try Self.roundTrips(
        SaveReadingPosition(content: .item(Fixture.item), position: .item(Fixture.item, .quote(TextQuote("打分"))))))
    #expect(try Self.roundTrips(MarkRead(content: .item(Fixture.item))))
    #expect(try Self.roundTrips(SendMessage(to: .item(Fixture.item), text: "Why?", passage: passage)))
    #expect(try Self.roundTrips(SendMessage(to: .main, text: "在吗")))
    #expect(try Self.roundTrips(StopTurn(in: .main)))
    #expect(try Self.roundTrips(StartOver(in: .item(Fixture.item))))
    #expect(
      try Self.roundTrips(
        SetConversationRuntime(Runtime(provider: .codex, model: "gpt-6.1-sol", effort: .high), for: .item(Fixture.item))
      ))
    #expect(try Self.roundTrips(ReadConversationRuntime(.project(Fixture.id(40)))))
    #expect(try Self.roundTrips(SaveSoul(core: "# Soul\n\nYou are Loci.")))
    #expect(try Self.roundTrips(Forget("- 2026-11-02 先给结论", in: .memory)))
    #expect(try Self.roundTrips(SetAvatar(try Avatar(data: Data([1, 2, 3]), format: "PNG"))))
    #expect(try Self.roundTrips(ResetAvatar()))
    let every = Every.week(.friday, at: try #require(TimeOfDay("21:00")))
    let draft = ScheduleDraft(title: "动静", follow: "看看", every: every, destination: .panel("radar"))
    #expect(try Self.roundTrips(AddSchedule("sandbox-news", draft)))
    #expect(try Self.roundTrips(AddFollowUp(.at(try #require(Day("2025-11-21")), nil), "看看 #244", in: .main)))
    #expect(try Self.roundTrips(AddFollowUp(.after(minutes: 90), "再看")))
    #expect(try Self.roundTrips(PauseSchedule(.panel(PanelRef("radar")), paused: true)))
    #expect(try Self.roundTrips(ChangeSchedule(.schedule(Fixture.item), every: .hour)))
    #expect(try Self.roundTrips(ChangeSchedule(.schedule(Fixture.item), ScheduleChange(destination: .notes))))
    #expect(try Self.roundTrips(ChangeSchedule(.panel(PanelRef("radar")), ScheduleChange(title: "雷达", follow: "看看"))))
    #expect(try Self.roundTrips(RemoveSchedule(.schedule(Fixture.item))))
    #expect(try Self.roundTrips(CancelFollowUp(Fixture.item)))
    #expect(try Self.roundTrips(ListTimers()))
    #expect(try Self.roundTrips(SetWholeThought(item: Fixture.item, thought: "拆得好")))
    #expect(try Self.roundTrips(SetWholeThought(item: Fixture.item, thought: nil)))
  }

  @Test func aPassageOverAPictureNamesThePicture() throws {
    let passage = Passage(
      locator: .item(Fixture.item, .quote(try TextQuote("\u{FFFC}"))), excerpt: "", pictures: ["images/a.png"])
    let quoted = QuotedPassage(
      locator: passage.locator, excerpt: "", pictures: ["images/a.png"], note: Fixture.id(4))

    #expect(try Self.roundTrips(SendMessage(to: .item(Fixture.item), text: "这张图在说什么", passage: passage)))
    #expect(try Self.roundTrips(quoted))
  }

  @Test func aPassageFromAnEarlierVersionHasNoPictures() throws {
    let locator = Locator.item(Fixture.item, .quote(try TextQuote("打分")))
    let passage = try Fixture.decode(Passage.self, #"{"locator":"\#(locator)","excerpt":"打分"}"#)
    let quoted = try Fixture.decode(
      QuotedPassage.self, #"{"locator":"\#(locator)","excerpt":"打分","note":"\#(Fixture.id(4))"}"#)

    #expect(passage.pictures.isEmpty)
    #expect(quoted.pictures.isEmpty)
  }

  @Test func everyReplyAndFeedSurvivesJSON() throws {
    let item = try Item(id: Fixture.item, kind: .video(duration: .seconds(90)), title: "Talk")
    let problem = FileProblem(path: "library/x/item.json", kind: .invalid, reason: "bad", subject: .item(item.id))
    let health = Health(database: .failed("disk full"), readingStateLost: true, fileProblems: [problem])
    let hit = SearchHit(target: .note(Fixture.item, on: .item(Fixture.item)), field: .note, snippet: "…", locator: nil)

    #expect(try Self.roundTrips(ItemPage(item: item, text: nil)))
    #expect(try Self.roundTrips(health))
    #expect(try Self.roundTrips([hit]))
    #expect(try Self.roundTrips(Done()))
    #expect(try Self.roundTrips(Feed<[Item]>.unavailable(.invalidFile(problem))))
    #expect(try Self.roundTrips(Optional<ReadingState>.none))
    #expect(
      try Self.decodesEqual(
        Set<ContentChange>([.item(Fixture.item), .conversation(.main), .loci(.soul), .turnEnded(.item(item.id))])))
    #expect(try Self.roundTrips(HostStartError.databaseFromNewerVersion(unknownMigrations: ["9 x"])))
  }

  @Test func aConversationWithEventsSurvivesJSON() throws {
    let item = try Item(id: Fixture.item, kind: .article, title: "How we built Pingora")
    let prompt = Message(id: Fixture.id(20), at: Fixture.instant, body: .prompt(Prompt(text: "在吗", purpose: .chat)))
    let job = Job(item: item.id, stage: .download, state: .running(progress: nil))
    let conversation = Conversation(
      ref: .main,
      entries: [
        .message(prompt), .event(WorldEvent(id: Fixture.id(21), at: Fixture.instant, kind: .finishedReading(item))),
        .event(WorldEvent(id: Fixture.id(22), at: Fixture.instant, kind: .saved(item, job: job))),
        .message(Message(id: Fixture.id(23), at: Fixture.instant, body: .startedOver)),
      ],
      turn: LiveTurn(startedAt: Fixture.instant, messages: [prompt]), context: ContextUsage(used: 10, window: 100))

    #expect(try Self.roundTrips(Feed<Conversation>.value(conversation)))
    #expect(conversation.entries.map(\.id) == [Fixture.id(20), Fixture.id(21), Fixture.id(22), Fixture.id(23)])
    #expect(try Self.roundTrips(Prompt(text: "look back", purpose: .review(Self.day))))
    for ending in [
      TurnEnding.interrupted, .failed("quota"), .unstarted(.codex, .notInstalled), .unstarted(.pi, .wouldNotStart),
    ] {
      #expect(try Self.roundTrips(Message.Body.ended(ending)))
    }
  }

  @Test func theLociPageSurvivesJSON() throws {
    let locator = Locator.item(Fixture.item, .quote(try TextQuote("term")))
    let entry = MemoryEntry(
      day: Self.day, text: "混淆过 term 和 index", source: .init(locator: locator, itemTitle: "Raft"), line: "- …")
    let page = LociPage(
      soul: Soul(core: "You are Loci.", traits: [.entry(Trait(day: Self.day, text: "爱画图")), .text("??")]),
      memory: [.entry(entry), .text("## 杂项")], profile: [],
      today: DayNotes(
        day: Self.day,
        notes: [.entry(DayNote(time: TimeOfDay("09:12"), text: "图画好了", from: .item(Fixture.item, title: nil)))]),
      diaries: [Diary.Heading(day: Self.day, writtenAt: TimeOfDay("23:48"), title: "一点十分")],
      together: Together(days: 17, messages: 214, itemsReadTogether: 38))

    #expect(try Self.roundTrips(Feed<LociPage>.value(page)))
    #expect(try Self.roundTrips(Diary(heading: page.diaries[0], body: "今天…", toRemember: ["地基"])))
    #expect(try Self.roundTrips(LociStatus(work: .refreshing(title: "沙箱雷达"))))
    #expect(try Self.roundTrips(Feed<Avatar?>.value(nil)))
  }

  @Test func anAvatarIsAPictureOfAKnownFormatAndSize() throws {
    #expect(try Avatar(data: Data([1]), format: "JPG").format == "jpg")
    #expect(throws: ModelError.self) { try Avatar(data: Data([1]), format: "svg") }
    #expect(throws: ModelError.self) { try Avatar(data: Data(), format: "png") }
    #expect(throws: ModelError.self) { try Avatar(data: Data(count: Avatar.largest + 1), format: "png") }
    let json = #"{"data":"AQ==","format":"exe"}"#
    #expect(throws: DecodingError.self) { try JSONDecoder().decode(Avatar.self, from: Data(json.utf8)) }
  }

  @Test(arguments: [true, false])
  func aNewWindowCanReadAnOlderHostsLociStatus(working: Bool) throws {
    let older = Feed.value(PreviousLociStatus(working: working))
    let data = try JSONEncoder().encode(older)
    let current = try JSONDecoder().decode(Feed<LociStatus>.self, from: data)

    #expect(current == .value(LociStatus(work: working ? .unspecified : nil)))
  }

  @Test(arguments: [LociWork?.none, .refreshing(title: "沙箱雷达")])
  func anOlderWindowCanReadANewHostsLociStatus(work: LociWork?) throws {
    let current = Feed.value(LociStatus(work: work))
    let data = try JSONEncoder().encode(current)
    let older = try JSONDecoder().decode(Feed<PreviousLociStatus>.self, from: data)

    #expect(older == .value(PreviousLociStatus(working: work != nil)))
    #expect(try JSONDecoder().decode(Feed<LociStatus>.self, from: data) == current)
  }

  private struct PreviousLociStatus: Codable, Equatable {
    let working: Bool
  }

  @Test func aRuntimeKeepsOnlyWhatItsProviderTakes() throws {
    let runtime = Runtime(provider: .grok, model: "  ", effort: .high)

    #expect(runtime.model == nil)
    #expect(runtime.effort == nil)
    #expect(Runtime(provider: .pi, model: " m ", effort: .off) == Runtime(provider: .pi, model: "m", effort: .off))
    let json = #"{"provider":"codex","effort":"off"}"#
    #expect(try JSONDecoder().decode(Runtime.self, from: Data(json.utf8)).effort == nil)
  }

  @Test func commandAndSubscriptionNamesAreUnique() {
    let commands = [
      AddTextItem.name, DeleteItems.name, RestoreDeleted.name, RenameItem.name, SetCover.name, ListItems.name,
      ReadItemText.name, Search.name, ReadReadingState.name,
      SaveReadingPosition.name, MarkRead.name, SendMessage.name, StopTurn.name, StartOver.name,
      ReadConversationRuntime.name,
      SetConversationRuntime.name, SetDefaultRuntime.name, DetectAgents.name, DataLocation.name, SaveSoul.name,
      Forget.name,
      SetAvatar.name, ResetAvatar.name,
    ]
    let subscriptions = [
      AllItems.name, OneItem.name, HealthReport.name, OneConversation.name, ConversationRuntime.name, LociWorking.name,
      LociHome.name, OneDiary.name, LociAvatar.name, AgentModelList.name, RuntimeOverview.name, CompanionPresence.name,
    ]

    #expect(Set(commands).count == commands.count)
    #expect(Set(subscriptions).count == subscriptions.count)
  }

  @Test func eachSubscriptionListensOnlyToWhatItShows() {
    let other = Fixture.id(9)
    #expect(AllItems().isAffected(by: [.item(other)]))
    #expect(!AllItems().isAffected(by: [.conversation(.main), .loci(.soul)]))
    #expect(!OneItem(item: Fixture.item).isAffected(by: [.item(other), .notes(.item(Fixture.item))]))
    #expect(OneItem(item: other).isAffected(by: [.everything]))
    #expect(LociHome().isAffected(by: [.loci(.memory)]))
    #expect(LociHome().isAffected(by: [.turnEnded(.main)]))
    #expect(!LociHome().isAffected(by: [.loci(.avatar), .conversation(.main)]))
    #expect(LociAvatar().isAffected(by: [.loci(.avatar)]))
    #expect(!LociAvatar().isAffected(by: [.loci(.soul)]))
    #expect(OneDiary(day: Self.day).isAffected(by: [.loci(.diary)]))
    #expect(LociWorking().isAffected(by: [.review]))
    #expect(ConversationRuntime(.main).isAffected(by: [.runtime]))
  }

  @Test func libraryActivityDoesNotRefreshTheMainConversation() {
    let other = Fixture.id(9)
    let main = OneConversation(.main)
    let onItem = OneConversation(.item(Fixture.item))

    #expect(!main.isAffected(by: [.job(Fixture.item), .item(Fixture.item), .reading(.item(Fixture.item))]))
    #expect(main.isAffected(by: [.conversation(.main)]))
    #expect(!main.isAffected(by: [.conversation(.item(Fixture.item))]))
    #expect(onItem.isAffected(by: [.conversation(.item(Fixture.item))]))
    #expect(onItem.isAffected(by: [.item(Fixture.item)]))
    #expect(!onItem.isAffected(by: [.job(Fixture.item), .item(other), .conversation(.main)]))
  }
}
