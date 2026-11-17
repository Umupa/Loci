import Foundation
import LociModel
import Testing

@testable import LociHost
@testable import LociStore

struct NoteScenarioTests {
  static func lesson(_ host: LocalHost, _ place: Place) async throws -> LessonRef {
    try await LessonScenarioTests.mentorWithLessons(host, place).0
  }

  /// α2-S5: a highlight with a thought is still there after the app quits and opens again.
  @Test func aHighlightAndItsThoughtSurviveARestart() async throws {
    let place = Place()
    defer { place.remove() }
    let world = TestWorld()
    let host = try await LocalHost.start(root: place.root, database: place.database, environment: world.environment)
    let lesson = try await Self.lesson(host, place)
    let locator = Locator.lesson(lesson, try TextQuote("不合适的节点"))

    let note = try await host.run(AddNote(locator: locator, excerpt: "不合适的节点", thought: "  资源还是端口？ "))
    await host.close()
    let reopened = try await LocalHost.start(
      root: place.root, database: place.database, environment: world.environment)
    defer { Task { await reopened.close() } }

    let notes = try #require(await value(reopened.subscribe(NotesOn(content: .lesson(lesson)))) { !$0.isEmpty })
    #expect(notes == [note])
    #expect(note.thought == "资源还是端口？")
    #expect(note.excerpt == "不合适的节点")
    #expect(note.savedAt == TestWorld.instant)
  }

  @Test func aThoughtCanBeChangedAndRemovedWithoutLosingTheHighlight() async throws {
    try await withHost { host, place, _ in
      let lesson = try await Self.lesson(host, place)
      let content = ContentRef.lesson(lesson)
      let notes = host.subscribe(NotesOn(content: content))
      let note = try await host.run(
        AddNote(locator: .lesson(lesson, try TextQuote("节点")), excerpt: "节点", thought: "第一个想法"))

      _ = try await host.run(SetNoteThought(content: content, note: note.id, thought: "改过的想法"))
      let changed = await value(notes) { $0.map(\.thought) == ["改过的想法"] }
      #expect(changed != nil)

      _ = try await host.run(SetNoteThought(content: content, note: note.id, thought: " "))
      let plain = await value(notes) { $0.count == 1 && $0[0].thought == nil && $0[0].excerpt == "节点" }
      #expect(plain != nil)
    }
  }

  @Test func aDeletedNoteIsGoneButTheFileOnlyGrew() async throws {
    try await withHost { host, place, _ in
      let lesson = try await Self.lesson(host, place)
      let content = ContentRef.lesson(lesson)
      let notes = host.subscribe(NotesOn(content: content))
      let note = try await host.run(AddNote(locator: .lesson(lesson, try TextQuote("节点")), excerpt: "节点"))

      _ = try await host.run(DeleteNote(content: content, note: note.id))

      let gone = await value(notes) { $0.isEmpty }
      #expect(gone != nil)
      let lines = try String(contentsOf: place.store.notesFile(on: content), encoding: .utf8)
        .split(separator: "\n")
      #expect(lines.count == 2)
      await #expect(throws: HostError.notFound(note.id.description)) {
        try await host.run(DeleteNote(content: content, note: note.id))
      }
    }
  }

  @Test func aNoteOnlyAddsWhereItPoints() async throws {
    try await withHost { host, place, world in
      let lesson = try await Self.lesson(host, place)
      let item = world.nextID()
      let note = try await host.run(AddNote(locator: .item(item, .quote(try TextQuote("别处"))), excerpt: "别处"))

      #expect(try await host.run(SetNoteThought(content: .item(item), note: note.id, thought: "x")).thought == "x")
      await #expect(throws: HostError.self) {
        try await host.run(SetNoteThought(content: .lesson(lesson), note: note.id, thought: "x"))
      }
    }
  }
}
