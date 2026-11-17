import Foundation
import LociModel
import Testing

@testable import LociStore

struct SnapshotTests {
  @Test func everythingInTheFolderIsReadInOnePass() throws {
    try withStore { store in
      let mentor = try Fixture.mentor()
      let item = try Fixture.item()
      let ref = LessonRef(mentor: mentor.id, lesson: Fixture.slug("intro"))
      let note = try Note(id: Fixture.id(10), locator: .lesson(ref, try TextQuote("x")), savedAt: Fixture.instant)
      try store.create(mentor)
      try store.add(item, content: "text")
      try store.save(LessonText(front: try Lesson.Front(sources: [.item(item.id)]), body: "x"), as: ref)
      try store.append(.saved(note), on: .lesson(ref))

      let snapshot = store.load()

      #expect(snapshot.mentors.map(\.mentor) == [mentor])
      #expect(snapshot.mentors.first?.catalog == (try Catalog(chapters: [])))
      #expect(snapshot.mentors.first?.citations == [Citation(lesson: ref, item: item.id, anchor: nil)])
      #expect(snapshot.items == [item])
      #expect(snapshot.notes == [.lesson(ref): [note]])
      #expect(snapshot.problems.isEmpty)
    }
  }

  @Test func anEmptyFolderHoldsNothing() throws {
    try withStore { store in
      let snapshot = store.load()

      #expect(snapshot.mentors.isEmpty && snapshot.items.isEmpty && snapshot.notes.isEmpty && snapshot.problems.isEmpty)
    }
  }

  @Test func eachBrokenFileTakesOutOnlyItsOwnContents() throws {
    try withStore { store in
      let good = try Fixture.mentor(1)
      let badCatalog = try Fixture.mentor(2, name: "catalog")
      let unknownProvider = try Fixture.mentor(3, name: "provider")
      let item = try Fixture.item(4)
      let badItem = try Fixture.item(5, title: "bad")
      for mentor in [good, badCatalog, unknownProvider] { try store.create(mentor) }
      try store.add(item, content: "text")
      try store.add(badItem, content: "text")
      let catalogFolder = try store.folderName(ofMentor: badCatalog.id)
      let providerFolder = try store.folderName(ofMentor: unknownProvider.id)
      let goodFolder = try store.folderName(ofMentor: good.id)
      let badItemFolder = try store.itemFolder(badItem.id).lastPathComponent

      try store.writeFile(
        "mentors/\(catalogFolder)/catalog.yaml",
        "chapters:\n- title: A\n  lessons:\n  - {slug: x, title: one}\n  - {slug: x, title: two}\n")
      try store.writeFile(
        "mentors/\(providerFolder)/mentor.json",
        try store.readFile("mentors/\(providerFolder)/mentor.json").replacing("claude-code", with: "claude"))
      try store.writeFile("library/\(badItemFolder)/item.json", "{")
      try store.writeFile(
        "mentors/\(goodFolder)/lessons/broken-front.md", "---\nsources: [\n---\nloci://library/\(item.id)#t=1")
      try store.writeFile("mentors/\(goodFolder)/lessons/Bad Name.md", "text")
      try store.writeFile("mentors/\(goodFolder)/lessons/bad-link.md", "loci://library/\(item.id)#t=9,1")

      let snapshot = store.load()

      #expect(snapshot.mentors.map(\.mentor.id) == [badCatalog.id, good.id])
      #expect(snapshot.mentors.first { $0.mentor.id == badCatalog.id }?.catalog == nil)
      #expect(
        snapshot.mentors.first { $0.mentor.id == good.id }?.citations == [
          Citation(
            lesson: LessonRef(mentor: good.id, lesson: Fixture.slug("broken-front")), item: item.id,
            anchor: .time(try TimeSpan(start: .seconds(1))))
        ])
      #expect(snapshot.items == [item])
      #expect(
        Set(snapshot.problems.map { "\($0.kind) \($0.path)" }) == [
          "invalid mentors/\(catalogFolder)/catalog.yaml",
          "invalid mentors/\(providerFolder)/mentor.json",
          "invalid library/\(badItemFolder)/item.json",
          "invalid mentors/\(goodFolder)/lessons/broken-front.md",
          "misnamed mentors/\(goodFolder)/lessons/Bad Name.md",
          "brokenLocator mentors/\(goodFolder)/lessons/bad-link.md",
        ])
    }
  }

  @Test func aCopiedFolderWithTheSameIDIsReportedAndTheOriginalKept() throws {
    try withStore { store in
      let mentor = try Fixture.mentor()
      try store.create(mentor)
      let original = try store.folderName(ofMentor: mentor.id)
      try FileManager.default.copyItem(
        at: store.root.appending(path: "mentors/\(original)"), to: store.root.appending(path: "mentors/a copy"))

      let snapshot = store.load()

      #expect(snapshot.mentors.map(\.mentor) == [mentor])
      #expect(
        snapshot.problems == [
          FileProblem(
            path: "mentors/a copy", kind: .duplicateID, reason: "another folder already holds \(mentor.id)",
            subject: .mentor(mentor.id))
        ])
      #expect(try store.folderName(ofMentor: mentor.id) == original)
    }
  }

  @Test func eachProblemNamesWhoseFileItIs() throws {
    try withStore { store in
      let mentor = try Fixture.mentor()
      let item = try Fixture.item()
      try store.create(mentor)
      try store.add(item, content: "text")
      let folder = try store.folderName(ofMentor: mentor.id)
      let itemFolder = try store.itemFolder(item.id).lastPathComponent
      try store.writeFile("mentors/\(folder)/catalog.yaml", "chapters: [")
      try store.writeFile("library/\(itemFolder)/item.json", #"{"id":"\#(item.id)","kind":"podcast","title":"x"}"#)
      try store.writeFile("notes/library/\(item.id).jsonl", "{\n")

      let subjects = Set(store.load().problems.map(\.subject))

      #expect(subjects == [.mentor(mentor.id), .item(item.id), .notes(.item(item.id))])
      #expect(store.loadMentor(mentor.id).problems.map(\.subject) == [.mentor(mentor.id)])
    }
  }
}
