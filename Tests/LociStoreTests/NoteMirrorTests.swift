import LociModel
import Testing

@testable import LociStore

struct NoteMirrorTests {
  @Test func editingAndDeletingNotesReplaceTheirMirrorAndSearchEntries() throws {
    try withStore { store in
      let library = try Library(store: store)
      let database = try StoreDatabase.inMemory()
      try database.rebuild(from: store)
      let content = ContentRef.item(library.article.id)
      let updated = try Note(
        id: library.note.id, locator: library.note.locator, thought: "replacementword", savedAt: Fixture.instant)
      try store.append(.saved(updated), on: content)
      try database.apply([.notes(content)], from: store)

      #expect(try database.notes(on: content) == [updated])
      #expect(try database.search("replacementword").count == 1)
      #expect(try database.search("漏斗").isEmpty)
      try store.append(.deleted(updated.id, at: Fixture.instant), on: content)
      try database.apply([.notes(content)], from: store)
      #expect(try database.notes(on: content).isEmpty)
      #expect(try database.search("replacementword").isEmpty)
    }
  }

  @Test func aRebuiltNoteMirrorKeepsExchangesAndDoesNotResurrectDeletedNotes() throws {
    try withStore { store in
      let library = try Library(store: store)
      let content = ContentRef.item(library.article.id)
      let second = try NotesTests.note(11, thought: "survivor", locator: library.note.locator)
      try store.append(.saved(second), on: content)
      try store.append(.deleted(second.id, at: Fixture.instant), on: content)
      try store.append(.saved(second), on: content)
      let database = try StoreDatabase.inMemory()

      try database.rebuild(from: store)

      #expect(try database.notes(on: content) == [library.note])
      #expect(try database.notes(on: content).first?.exchanges == library.note.exchanges)
      #expect(try database.search("survivor").isEmpty)
    }
  }
}
