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

  @Test func deletingAnItemCanKeepOrDeleteItsNotes() throws {
    try withStore { store in
      for (seed, choice) in [(2, NotesOnDelete.keep), (3, NotesOnDelete.delete)] as [(UInt64, NotesOnDelete)] {
        let item = try Fixture.item(seed)
        try store.add(item, content: "text")
        try store.append(.deleted(Fixture.id(9), at: Fixture.instant), on: .item(item.id))
        try store.deleteItem(item.id, notes: choice)

        #expect(throws: StoreError.notFound(item.id.description)) { try store.item(item.id) }
        let notesFile = store.root.appending(path: "notes/library/\(item.id).jsonl")
        #expect(FileManager.default.fileExists(atPath: notesFile.path(percentEncoded: false)) == (choice == .keep))
      }
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
