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

      #expect(mirrors["mentor"]?.count == 2)
      #expect(mirrors["lesson"]?.count == 2)
      #expect(mirrors["citation"]?.count == 4)
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

      let renamed = try Mentor(
        id: library.first.id, name: "排程", avatar: "owl", color: library.first.color, provider: .pi)
      try store.save(renamed)
      try store.save(
        try Catalog(chapters: [
          .init(
            title: "新的一章",
            lessons: [
              try Lesson(slug: Fixture.slug("intro"), title: "开始"),
              try Lesson(slug: library.firstLesson.lesson, title: "过滤与打分"),
            ])
        ]), of: library.first.id)
      let extra = LessonRef(mentor: library.first.id, lesson: Fixture.slug("not-in-catalog"))
      try store.save(LessonText(front: try Lesson.Front(sources: [.item(library.video.id)]), body: ""), as: extra)
      try store.deleteItem(library.article.id, notes: .keep)
      try store.deleteMentor(library.second.id, notes: .keep)
      let second = try Note(id: Fixture.id(11), locator: library.note.locator, thought: "再看", savedAt: Fixture.instant)
      try store.append(.saved(second), on: .item(library.article.id))
      let folder = try store.mentorFolder(library.first.id)
      try FileManager.default.moveItem(at: folder, to: folder.deletingLastPathComponent().appending(path: "renamed"))

      try followed.apply(
        [
          .mentor(library.first.id), .catalog(library.first.id), .lesson(extra), .item(library.article.id),
          .mentor(library.second.id), .notes(.item(library.article.id)),
        ], from: store)
      let rebuilt = try StoreDatabase.inMemory()
      try rebuilt.rebuild(from: store)

      #expect(try followed.mirrors() == rebuilt.mirrors())
      #expect(Set(try followed.citations(of: library.article.id).map(\.lesson)) == [library.firstLesson])
      #expect(try followed.search("排程").map(\.target) == [.mentor(library.first.id)])
      #expect(try followed.search("Distributed").isEmpty)
    }
  }

  @Test func everythingMeansRebuild() throws {
    try withStore { store in
      let library = try Library(store: store)
      let database = try StoreDatabase.inMemory()
      try store.deleteItem(library.video.id, notes: .keep)

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
      let folder = try store.folderName(ofMentor: library.first.id)
      try store.writeFile("mentors/\(folder)/catalog.yaml", "chapters: [")

      let problems = try database.apply([.catalog(library.first.id)], from: store)

      #expect(problems.map(\.path) == ["mentors/\(folder)/catalog.yaml"])
      #expect(try database.citations(in: library.firstLesson).count == 3)
    }
  }
}
