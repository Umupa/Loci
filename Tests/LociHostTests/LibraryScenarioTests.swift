import Foundation
import LociModel
import Testing

@testable import LociHost
@testable import LociStore

struct LibraryScenarioTests {
  /// α1-S3: a text file becomes an item that can be read in full.
  @Test func aTextFileBecomesAnItemToRead() async throws {
    try await withHost { host, _, _ in
      let items = host.subscribe(AllItems())
      let text = "# Large-scale cluster management at Google with Borg\n\nBorg admits, schedules, starts…\n"
      let item = try await host.run(AddTextItem(fileName: "borg.md", text: text))

      #expect(item.title == "Large-scale cluster management at Google with Borg")
      #expect(item.kind == .article)
      let listed = await value(items) { $0 == [item] }
      #expect(listed != nil)
      #expect(try await host.run(ReadItemText(item: item.id)) == text)
    }
  }

  @Test func withoutAHeadingTheFileNameIsTheTitle() async throws {
    try await withHost { host, _, _ in
      let named = try await host.run(AddTextItem(fileName: "调度笔记.txt", text: "没有标题"))
      let dotted = try await host.run(AddTextItem(fileName: "notes.v2.md", text: ""))

      #expect(named.title == "调度笔记")
      #expect(dotted.title == "notes.v2")
      await #expect(throws: HostError.self) { try await host.run(AddTextItem(fileName: "", text: "no heading")) }
    }
  }

  /// α1-S6: a lesson citing an item is seen from the lesson and from the item.
  @Test func aCitationIsSeenFromBothSides() async throws {
    try await withHost { host, place, _ in
      let mentor = try await host.run(CreateMentor(request: "Scheduling"))
      let item = try await host.run(AddTextItem(fileName: "borg.md", text: "# Borg\n\nfeasibility checking\n"))
      let page = host.subscribe(OneItem(item: item.id))
      let uncited = await value(page) { $0.citedBy.isEmpty }
      #expect(uncited != nil)

      let lesson = LessonRef(mentor: mentor.id, lesson: Lesson.Slug("filter")!)
      try place.store.save(
        try Catalog(chapters: [.init(title: "基础", lessons: [try Lesson(slug: lesson.lesson, title: "过滤")])]),
        of: mentor.id)
      try place.store.save(
        LessonText(
          front: try Lesson.Front(sources: [.item(item.id)]),
          body: "[原文](loci://library/\(item.id)#quote=feasibility%20checking)\n"),
        as: lesson)

      let cited = await value(page) { $0.citedBy.count == 2 && $0.citedBy.allSatisfy { $0.lessonTitle == "过滤" } }
      #expect(cited?.citedBy.map(\.mentorName) == ["Scheduling", "Scheduling"])
      #expect(cited?.text == "# Borg\n\nfeasibility checking\n")
      #expect(
        try await host.run(LessonCitations(lesson: lesson)) == [
          Citation(lesson: lesson, item: item.id, anchor: nil),
          Citation(lesson: lesson, item: item.id, anchor: .quote(try TextQuote("feasibility checking"))),
        ])
      #expect(try await host.run(ItemCitations(item: item.id)).count == 2)
    }
  }

  @Test func deletingAnItemEmptiesItsPage() async throws {
    try await withHost { host, _, _ in
      let item = try await host.run(AddTextItem(fileName: "a.md", text: "text"))
      let items = host.subscribe(AllItems())
      let listed = await value(items) { $0 == [item] }
      #expect(listed != nil)

      _ = try await host.run(DeleteItem(item: item.id, notes: .delete))

      let emptied = await value(items) { $0.isEmpty }
      #expect(emptied != nil)
      await #expect(throws: HostError.notFound(item.id.description)) {
        try await host.run(ReadItemText(item: item.id))
      }
    }
  }

  @Test func searchAndReadingStateGoThroughTheHost() async throws {
    try await withHost { host, _, world in
      let item = try await host.run(AddTextItem(fileName: "a.md", text: "# 调度器\n\n过滤与打分\n"))
      let content = ContentRef.item(item.id)
      let state = ReadingState(
        position: .item(item.id, .quote(try TextQuote("打分"))), finished: false, updatedAt: TestWorld.instant)

      let hits = try await host.run(Search(text: "调度"))

      #expect(Set(hits.map(\.target)) == [.item(item.id)])
      #expect(Set(hits.map(\.field)) == [.title, .body])
      #expect(try await host.run(ReadReadingState(content: content)) == nil)
      _ = try await host.run(SaveReadingState(content: content, state: state))
      #expect(try await host.run(ReadReadingState(content: content)) == state)
      await #expect(throws: HostError.self) {
        try await host.run(SaveReadingState(content: .item(world.nextID()), state: state))
      }
    }
  }
}
