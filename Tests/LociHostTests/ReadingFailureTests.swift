import LociModel
import Testing

@testable import LociHost
@testable import LociStore

struct ReadingFailureTests {
  @Test func savingANewPositionKeepsTheReadMarkAndMarkingReadKeepsThePosition() async throws {
    try await withHost { host, _, _ in
      let item = try await NoteScenarioTests.article(host)
      let content = ContentRef.item(item)
      let first = Locator.item(item, .quote(try TextQuote("不合适的节点")))
      #expect(try await host.run(ReadReadingState(content: content)) == nil)
      _ = try await host.run(SaveReadingPosition(content: content, position: first))
      _ = try await host.run(MarkRead(content: content))
      #expect(
        try await host.run(ReadReadingState(content: content))
          == ReadingState(position: first, finished: true, updatedAt: TestWorld.instant))
      let second = Locator.item(item, .quote(try TextQuote("先排除")))
      _ = try await host.run(SaveReadingPosition(content: content, position: second))
      #expect(
        try await host.run(ReadReadingState(content: content))
          == ReadingState(position: second, finished: true, updatedAt: TestWorld.instant))
    }
  }

  @Test func anInvalidPositionDoesNotOverwriteTheLastGoodOne() async throws {
    try await withHost { host, _, world in
      let item = try await NoteScenarioTests.article(host)
      let content = ContentRef.item(item)
      let position = Locator.item(item, .quote(try TextQuote("节点")))
      _ = try await host.run(SaveReadingPosition(content: content, position: position))

      await #expect(throws: HostError.self) {
        try await host.run(
          SaveReadingPosition(content: content, position: .item(world.nextID(), .quote(try TextQuote("elsewhere")))))
      }
      #expect(try await host.run(ReadReadingState(content: content))?.position == position)
    }
  }

  @Test func aLostPassageKeepsItsNoteAndCanBeDeleted() async throws {
    try await withHost { host, place, _ in
      let item = try await NoteScenarioTests.article(host)
      let quote = try TextQuote("不合适的节点")
      let note = try await host.run(
        AddNote(locator: .item(item, .quote(quote)), excerpt: quote.text, thought: "keep this"))
      let file = try #require(try place.store.itemFiles(item).content)
      try place.edit(file) { _ in "完全改写的文章。" }
      await host.follow([.item(item)])

      #expect(try quote.range(in: await host.itemText(item)) == nil)
      #expect(try await host.notes(on: .item(item)) == [note])
      _ = try await host.run(DeleteNote(content: .item(item), note: note.id))
      #expect(try await host.notes(on: .item(item)).isEmpty)
    }
  }
}
