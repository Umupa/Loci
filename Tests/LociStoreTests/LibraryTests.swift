import Foundation
import LociModel
import Testing

@testable import LociStore

struct LibraryTests {
  @Test func anAddedItemReadsBackWithItsText() throws {
    try withStore { store in
      let item = try Fixture.item()
      try store.add(item, content: "# Borg\n\nGoogle's cluster manager.\n")

      #expect(try store.item(item.id) == item)
      #expect(try store.content(of: item.id) == "# Borg\n\nGoogle's cluster manager.\n")
      #expect(
        try store.readFile("library/large-scale-cluster-management-at-google-\(item.id)/item.json") == """
          {
            "authors" : [
              "Abhishek Verma"
            ],
            "id" : "\(item.id)",
            "kind" : "article",
            "language" : "en",
            "title" : "Large-scale cluster management at Google with Borg"
          }

          """)
    }
  }

  @Test func savingAnItemKeepsItsContent() throws {
    try withStore { store in
      let item = try Fixture.item()
      try store.add(item, content: "text")
      let retitled = try Item(id: item.id, kind: .paper, title: "Borg")
      try store.save(retitled)

      #expect(try store.item(item.id) == retitled)
      #expect(try store.content(of: item.id) == "text")
    }
  }

  @Test func anItemSetAsideLeavesTheLibraryWithItsNotesAndComesBackAsItWas() throws {
    try withStore { store in
      let item = try Fixture.item()
      try store.add(item, content: "text")
      try store.append(.deleted(Fixture.id(9), at: Fixture.instant), on: .item(item.id))
      let folder = try store.itemFolder(item.id).lastPathComponent
      let notesFile = store.root.appending(path: "notes/library/\(item.id).jsonl")

      try store.setAside(item.id)

      #expect(throws: StoreError.notFound(item.id.description)) { try store.item(item.id) }
      #expect(!FileManager.default.fileExists(atPath: notesFile.path(percentEncoded: false)))
      #expect(store.setAsideItems() == [item.id])

      try store.restore(item.id)

      #expect(try store.item(item.id) == item)
      #expect(try store.itemFolder(item.id).lastPathComponent == folder)
      #expect(try store.content(of: item.id) == "text")
      #expect(FileManager.default.fileExists(atPath: notesFile.path(percentEncoded: false)))
      #expect(store.setAsideItems().isEmpty)
    }
  }

  @Test func anItemSetAsideCanBeDiscardedForGood() throws {
    try withStore { store in
      let item = try Fixture.item()
      try store.add(item, content: "text")
      try store.setAside(item.id)

      try store.discardSetAside(item.id)

      #expect(store.setAsideItems().isEmpty)
      #expect(throws: StoreError.notFound(item.id.description)) { try store.item(item.id) }
    }
  }

  @Test func aFailedEncodingLeavesTheOldFileAsItWas() throws {
    struct Unwritable: Encodable {
      func encode(to encoder: any Encoder) throws {
        throw EncodingError.invalidValue(0, .init(codingPath: [], debugDescription: "no"))
      }
    }
    try withStore { store in
      let item = try Fixture.item()
      try store.add(item, content: "text")
      let url = try store.itemFolder(item.id).appending(path: Store.itemFile)
      let before = try Data(contentsOf: url)

      #expect(throws: EncodingError.self) { try store.write(Formats.document(Unwritable()), to: url) }
      #expect(try Data(contentsOf: url) == before)
    }
  }
}
