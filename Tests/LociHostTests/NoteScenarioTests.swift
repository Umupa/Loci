import Foundation
import LociModel
import Testing

@testable import LociHost
@testable import LociStore

struct NoteScenarioTests {
  static func article(_ host: LocalHost) async throws -> EntityID {
    try await host.run(AddTextItem(fileName: "filter.md", text: Fixture.schedulingText)).id
  }

  /// α2-S5: a highlight with a thought is still there after the app quits and opens again.
  @Test func aHighlightAndItsThoughtSurviveARestart() async throws {
    let place = Place()
    defer { place.remove() }
    let world = TestWorld()
    let host = try await LocalHost.start(root: place.root, database: place.database, environment: world.environment)
    let item = try await Self.article(host)
    let locator = Locator.item(item, .quote(try TextQuote("不合适的节点")))

    let note = try await host.run(AddNote(locator: locator, excerpt: "不合适的节点", thought: "  资源还是端口？ "))
    await host.close()
    let reopened = try await LocalHost.start(
      root: place.root, database: place.database, environment: world.environment)
    defer { Task { await reopened.close() } }

    let notes = try #require(await value(reopened.subscribe(NotesOn(content: .item(item)))) { !$0.isEmpty })
    #expect(notes == [note])
    #expect(note.thought == "资源还是端口？")
    #expect(note.excerpt == "不合适的节点")
    #expect(note.savedAt == TestWorld.instant)
  }

  @Test func aThoughtCanBeChangedAndRemovedWithoutLosingTheHighlight() async throws {
    try await withHost { host, place, _ in
      let item = try await Self.article(host)
      let content = ContentRef.item(item)
      let notes = host.subscribe(NotesOn(content: content))
      let note = try await host.run(
        AddNote(locator: .item(item, .quote(try TextQuote("节点"))), excerpt: "节点", thought: "第一个想法"))

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
      let item = try await Self.article(host)
      let content = ContentRef.item(item)
      let notes = host.subscribe(NotesOn(content: content))
      let note = try await host.run(AddNote(locator: .item(item, .quote(try TextQuote("节点"))), excerpt: "节点"))

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
    try await withHost { host, _, world in
      let article = try await Self.article(host)
      let item = world.nextID()
      let note = try await host.run(AddNote(locator: .item(item, .quote(try TextQuote("别处"))), excerpt: "别处"))

      #expect(try await host.run(SetNoteThought(content: .item(item), note: note.id, thought: "x")).thought == "x")
      await #expect(throws: HostError.self) {
        try await host.run(SetNoteThought(content: .item(article), note: note.id, thought: "x"))
      }
    }
  }

  /// HL-S6: an item has one thought on it as a whole, which can be changed and cleared.
  @Test func anItemKeepsOneThoughtOnTheWhole() async throws {
    try await withHost { host, _, _ in
      let item = try await Self.article(host)
      let notes = host.subscribe(NotesOn(content: .item(item)))

      let first = try #require(try await host.run(SetWholeThought(item: item, thought: " 拆得好 ")))
      let second = try #require(try await host.run(SetWholeThought(item: item, thought: "定时器和收件箱分开")))

      #expect(first.id == second.id)
      #expect(second.locator == .item(item, .whole))
      let one = await value(notes) { $0.map(\.thought) == ["定时器和收件箱分开"] }
      #expect(one?.first?.isWhole == true)

      #expect(try await host.run(SetWholeThought(item: item, thought: "  ")) == nil)
      #expect(await value(notes) { $0.isEmpty } != nil)
      #expect(try await host.run(SetWholeThought(item: item, thought: nil)) == nil)
    }
  }

  @Test func aThoughtOnTheWholeOfAnItemThatIsGoneIsRefused() async throws {
    try await withHost { host, _, world in
      let missing = world.nextID()
      await #expect(throws: HostError.notFound(missing.description)) {
        try await host.run(SetWholeThought(item: missing, thought: "x"))
      }
    }
  }

  /// HL-S2: the words of a highlight over a picture are kept without the picture's placeholder character.
  @Test func aHighlightOverAPictureKeepsTheWordsAndNamesThePicture() async throws {
    try await withHost { host, _, _ in
      let item = try await Self.article(host)
      let locator = Locator.item(item, .quote(try TextQuote("节点\u{FFFC}")))

      let both = try await host.run(
        AddNote(locator: locator, excerpt: "节点\n\u{FFFC}\n", pictures: ["images/a.png"]))
      let only = try await host.run(AddNote(locator: locator, excerpt: "\u{FFFC}", pictures: ["images/a.png"]))

      #expect(both.excerpt == "节点")
      #expect(both.pictures == ["images/a.png"])
      #expect(only.excerpt == nil)
      #expect(only.pictures == ["images/a.png"])
    }
  }
}
