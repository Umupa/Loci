import Foundation
import LociModel
import Testing

@testable import LociStore

struct SnapshotTests {
  @Test func everythingInTheFolderIsReadInOnePass() throws {
    try withStore { store in
      let item = try Fixture.item()
      let note = try Note(
        id: Fixture.id(10), locator: .item(item.id, .quote(try TextQuote("x"))), savedAt: Fixture.instant)
      try store.add(item, content: "text")
      try store.append(.saved(note), on: .item(item.id))

      let snapshot = store.load()

      #expect(snapshot.items == [item])
      #expect(snapshot.notes == [.item(item.id): [note]])
      #expect(snapshot.problems.isEmpty)
    }
  }

  @Test func anEmptyFolderHoldsNothing() throws {
    try withStore { store in
      let snapshot = store.load()

      #expect(snapshot.items.isEmpty && snapshot.notes.isEmpty && snapshot.problems.isEmpty)
    }
  }

  @Test func foldersAnEarlierVersionKeptForMentorsAreNotRead() throws {
    try withStore { store in
      try store.writeFile("mentors/diao-du/mentor.json", "{")
      try store.writeFile("notes/mentors/x/intro.jsonl", "{")

      #expect(store.load().problems.isEmpty)
    }
  }

  @Test func eachBrokenFileTakesOutOnlyItsOwnContents() throws {
    try withStore { store in
      let item = try Fixture.item(4)
      let badItem = try Fixture.item(5, title: "bad")
      try store.add(item, content: "text")
      try store.add(badItem, content: "text")
      let badItemFolder = try store.itemFolder(badItem.id).lastPathComponent
      try store.writeFile("library/\(badItemFolder)/item.json", "{")

      let snapshot = store.load()

      #expect(snapshot.items == [item])
      #expect(snapshot.problems.map { "\($0.kind) \($0.path)" } == ["invalid library/\(badItemFolder)/item.json"])
    }
  }

  @Test func aCopiedFolderWithTheSameIDIsReportedAndTheOriginalKept() throws {
    try withStore { store in
      let item = try Fixture.item()
      try store.add(item, content: "text")
      let original = try store.itemFolder(item.id).lastPathComponent
      try FileManager.default.copyItem(
        at: store.root.appending(path: "library/\(original)"), to: store.root.appending(path: "library/a copy"))

      let snapshot = store.load()

      #expect(snapshot.items == [item])
      #expect(
        snapshot.problems == [
          FileProblem(
            path: "library/a copy", kind: .duplicateID, reason: "another folder already holds \(item.id)",
            subject: .item(item.id))
        ])
      #expect(try store.itemFolder(item.id).lastPathComponent == original)
    }
  }

  @Test func aFileWhoseIDCannotBeReadBelongsToTheIDInItsFolderName() throws {
    try withStore { store in
      let item = try Fixture.item()
      try store.add(item, content: "text")
      let folder = try store.itemFolder(item.id).lastPathComponent
      try store.writeFile("library/\(folder)/item.json", "{")

      #expect(store.load().problems.map(\.subject) == [.item(item.id)])
    }
  }

  @Test func eachProblemNamesWhoseFileItIs() throws {
    try withStore { store in
      let item = try Fixture.item()
      try store.add(item, content: "text")
      let itemFolder = try store.itemFolder(item.id).lastPathComponent
      try store.writeFile("library/\(itemFolder)/item.json", #"{"id":"\#(item.id)","kind":"podcast","title":"x"}"#)
      try store.writeFile("notes/library/\(item.id).jsonl", "{\n")

      #expect(Set(store.load().problems.map(\.subject)) == [.item(item.id), .notes(.item(item.id))])
    }
  }
}
