import Foundation
import LociModel
import Testing

@testable import LociStore

struct MirrorTests {
  @Test func aRebuildMirrorsEveryFile() throws {
    try withStore { store in
      let library = try Library(store: store)
      let database = try StoreDatabase.inMemory()

      #expect(try database.rebuild(from: store).isEmpty)
      let mirrors = try database.mirrors()

      #expect(mirrors["item"]?.count == 2)
      #expect(mirrors["note"]?.count == 1)
      #expect(try database.notes(on: .item(library.article.id)) == [library.note])
    }
  }

  @Test func rebuildingTwiceGivesTheSameTables() throws {
    try withStore { store in
      _ = try Library(store: store)
      let database = try StoreDatabase.inMemory()
      try database.rebuild(from: store)
      let once = try database.mirrors()
      try database.rebuild(from: store)

      #expect(try database.mirrors() == once)
    }
  }

  @Test func followingChangesGivesWhatARebuildGives() throws {
    try withStore { store in
      let library = try Library(store: store)
      let followed = try StoreDatabase.inMemory()
      try followed.rebuild(from: store)

      let retitled = try Item(id: library.video.id, kind: library.video.kind, title: "Borg at Google")
      try store.save(retitled)
      try store.deleteItem(library.article.id)
      let second = try Note(id: Fixture.id(11), locator: library.note.locator, thought: "再看", savedAt: Fixture.instant)
      try store.append(.saved(second), on: .item(library.article.id))
      let folder = try store.itemFolder(library.video.id)
      try FileManager.default.moveItem(at: folder, to: folder.deletingLastPathComponent().appending(path: "renamed"))

      try followed.apply(
        [.item(library.video.id), .item(library.article.id), .notes(.item(library.article.id))], from: store)
      let rebuilt = try StoreDatabase.inMemory()
      try rebuilt.rebuild(from: store)

      #expect(try followed.mirrors() == rebuilt.mirrors())
      #expect(try followed.search("Google").map(\.target) == [.item(library.video.id)])
      #expect(try followed.search("feasibility").filter { $0.target == .item(library.article.id) }.isEmpty)
    }
  }

  @Test func everythingMeansRebuild() throws {
    try withStore { store in
      let library = try Library(store: store)
      let database = try StoreDatabase.inMemory()
      try store.deleteItem(library.video.id)

      try database.apply([.everything, .item(library.article.id)], from: store)
      let rebuilt = try StoreDatabase.inMemory()
      try rebuilt.rebuild(from: store)

      #expect(try database.mirrors() == rebuilt.mirrors())
    }
  }

  @Test func problemsInTheFilesAreHandedBack() throws {
    try withStore { store in
      let library = try Library(store: store)
      let database = try StoreDatabase.inMemory()
      try database.rebuild(from: store)
      let folder = try store.itemFolder(library.video.id).lastPathComponent
      try store.writeFile("library/\(folder)/item.json", "{")

      let problems = try database.apply([.item(library.video.id)], from: store)

      #expect(problems.map(\.path) == ["library/\(folder)/item.json"])
      #expect(try database.items().map(\.id) == [library.article.id])
    }
  }
}
