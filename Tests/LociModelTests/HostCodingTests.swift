import Foundation
import Testing

@testable import LociModel

/// Everything that crosses the host protocol must survive the trip a remote host will give it.
struct HostCodingTests {
  static let lesson = LessonRef(mentor: Fixture.mentor, lesson: Lesson.Slug("intro")!)

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

  @Test func everyCommandSurvivesJSON() throws {
    let reading = ReadingState(
      position: .item(Fixture.item, .quote(try TextQuote("x"))), finished: true, updatedAt: Fixture.instant)
    #expect(try Self.roundTrips(CreateMentor(request: "我想学调度")))
    #expect(try Self.roundTrips(RenameMentor(mentor: Fixture.mentor, name: "调度")))
    #expect(try Self.roundTrips(DeleteMentor(mentor: Fixture.mentor, notes: .delete)))
    #expect(try Self.roundTrips(ListMentors()))
    #expect(try Self.roundTrips(ReadCatalog(mentor: Fixture.mentor)))
    #expect(try Self.roundTrips(AddTextItem(fileName: "a.md", text: "# A\n")))
    #expect(try Self.roundTrips(DeleteItem(item: Fixture.item, notes: .keep)))
    #expect(try Self.roundTrips(ListItems()))
    #expect(try Self.roundTrips(ReadItemText(item: Fixture.item)))
    #expect(try Self.roundTrips(ReadLessonText(lesson: Self.lesson)))
    #expect(try Self.roundTrips(LessonCitations(lesson: Self.lesson)))
    #expect(try Self.roundTrips(ItemCitations(item: Fixture.item)))
    #expect(try Self.roundTrips(Search(text: "调度", limit: 10)))
    #expect(try Self.roundTrips(ReadReadingState(content: .lesson(Self.lesson))))
    #expect(try Self.roundTrips(SaveReadingState(content: .item(Fixture.item), state: reading)))
  }

  @Test func everyReplyAndFeedSurvivesJSON() throws {
    let mentor = try Mentor(
      id: Fixture.mentor, name: "调度", avatar: "ember", color: MentorColor.palette[0], provider: .pi,
      permission: .full, request: "我想学调度")
    let item = try Item(id: Fixture.item, kind: .video(duration: .seconds(90)), title: "Talk")
    let citation = Citation(lesson: Self.lesson, item: Fixture.item, anchor: .time(try TimeSpan(start: .seconds(3))))
    let problem = FileProblem(
      path: "mentors/x/catalog.yaml", kind: .invalid, reason: "bad", subject: .mentor(mentor.id))
    let page = MentorPage(
      mentor: mentor, catalog: try Catalog(chapters: []), writtenLessons: [Lesson.Slug("intro")!])
    let itemPage = ItemPage(
      item: item, text: nil, citedBy: [CitingLesson(citation: citation, mentorName: "调度", lessonTitle: nil)])
    let health = Health(database: .failed("disk full"), readingStateLost: true, fileProblems: [problem])
    let hit = SearchHit(
      target: .note(Fixture.item, on: .lesson(Self.lesson)), field: .note, snippet: "…", locator: nil)

    #expect(try Self.roundTrips(page))
    #expect(try Self.roundTrips(itemPage))
    #expect(try Self.roundTrips(health))
    #expect(try Self.roundTrips([hit]))
    #expect(try Self.roundTrips(Citation(lesson: Self.lesson, item: Fixture.item, anchor: nil)))
    #expect(try Self.roundTrips(Done()))
    #expect(try Self.roundTrips(Feed<MentorPage>.value(page)))
    #expect(try Self.roundTrips(Feed<[Item]>.unavailable(.invalidFile(problem))))
    #expect(try Self.roundTrips(Optional<ReadingState>.none))
    #expect(try Self.decodesEqual(Set<ContentChange>([.lesson(Self.lesson), .item(Fixture.item), .everything])))
    #expect(try Self.roundTrips(HostStartError.databaseFromNewerVersion(unknownMigrations: ["9 x"])))
  }

  @Test func aCitationAnchoredInAnotherItemIsRejected() {
    let json =
      #"{"item":"\#(Fixture.item)","lesson":{"lesson":"intro","mentor":"\#(Fixture.mentor)"},"anchor":"loci://library/\#(Fixture.mentor)#t=1"}"#

    #expect(throws: DecodingError.self) { try JSONDecoder().decode(Citation.self, from: Data(json.utf8)) }
  }

  @Test func commandAndSubscriptionNamesAreUnique() {
    let commands = [
      CreateMentor.name, RenameMentor.name, DeleteMentor.name, ListMentors.name, ReadCatalog.name, AddTextItem.name,
      DeleteItem.name, ListItems.name, ReadItemText.name, ReadLessonText.name, LessonCitations.name, ItemCitations.name,
      Search.name,
      ReadReadingState.name, SaveReadingState.name,
    ]
    let subscriptions = [AllMentors.name, AllItems.name, OneMentor.name, OneItem.name, HealthReport.name]

    #expect(Set(commands).count == commands.count)
    #expect(Set(subscriptions).count == subscriptions.count)
  }

  @Test func newMentorsHaveDistinctLooksToChooseFrom() {
    #expect(Set(Mentor.portraits).count == Mentor.portraits.count)
    #expect(Set(MentorColor.palette).count == MentorColor.palette.count)
  }

  @Test func eachSubscriptionListensOnlyToWhatItShows() {
    let other = Fixture.id(9)
    #expect(AllMentors().isAffected(by: [.mentor(other)]))
    #expect(!AllMentors().isAffected(by: [.catalog(other), .notes(.item(other))]))
    #expect(AllItems().isAffected(by: [.item(other)]))
    #expect(!AllItems().isAffected(by: [.mentor(other)]))
    #expect(OneMentor(mentor: Fixture.mentor).isAffected(by: [.lesson(Self.lesson)]))
    #expect(!OneMentor(mentor: other).isAffected(by: [.lesson(Self.lesson), .item(Fixture.item)]))
    #expect(OneItem(item: Fixture.item).isAffected(by: [.lesson(Self.lesson)]))
    #expect(!OneItem(item: Fixture.item).isAffected(by: [.item(other), .notes(.item(Fixture.item))]))
    #expect(OneMentor(mentor: other).isAffected(by: [.everything]))
  }
}
