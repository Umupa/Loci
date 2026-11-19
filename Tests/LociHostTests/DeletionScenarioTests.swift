import Foundation
import LociModel
import Testing

@testable import LociHost

/// A-S7, A-S8, A-S9, A-S10: renaming, a new cover, and deleting that can be undone.
struct DeletionScenarioTests {
  @Test func deletedItemsLeaveAtOnceAndComeBackWithTheirHighlightsAndConversation() async throws {
    try await withHost { host, _, _ in
      let first = try await host.run(AddTextItem(fileName: "a.md", text: "# Raft\n\nterm\n"))
      let second = try await host.run(AddTextItem(fileName: "b.md", text: "# Paxos\n\nballot\n"))
      let note = try await host.run(
        AddNote(locator: .item(first.id, .quote(try TextQuote("term"))), excerpt: "term", thought: "选举"))
      _ = try await host.run(SendMessage(to: .item(first.id), text: "Why?"))
      _ = try #require(await settled(host, .item(first.id)))
      let items = host.subscribe(AllItems())

      _ = try await host.run(DeleteItems([first.id, second.id]))

      #expect(await value(items) { $0.isEmpty } != nil)
      await #expect(throws: HostError.self) { try await host.run(ReadItemText(item: first.id)) }

      let restored = try await host.run(RestoreDeleted())

      #expect(Set(restored.map(\.id)) == [first.id, second.id])
      #expect(await value(items) { Set($0.map(\.id)) == [first.id, second.id] } != nil)
      #expect(try await host.notes(on: .item(first.id)) == [note])
      #expect(try await host.conversation(.item(first.id)).entries.count == 2)
      #expect(try await host.run(RestoreDeleted()).isEmpty)
    }
  }

  @Test func onlyTheLatestDeletionCanBeUndone() async throws {
    try await withHost { host, _, _ in
      let first = try await host.run(AddTextItem(fileName: "a.md", text: "# Raft\n"))
      let second = try await host.run(AddTextItem(fileName: "b.md", text: "# Paxos\n"))

      _ = try await host.run(DeleteItems([first.id]))
      _ = try await host.run(DeleteItems([second.id]))
      let restored = try await host.run(RestoreDeleted())

      #expect(restored.map(\.id) == [second.id])
      #expect(try await host.listItems().map(\.id) == [second.id])
    }
  }

  @Test func whatWasDeletedIsGoneForGoodAfterTheAppQuits() async throws {
    let place = Place()
    defer { place.remove() }
    let world = TestWorld()
    let host = try await LocalHost.start(root: place.root, database: place.database, environment: world.environment)
    let item = try await host.run(AddTextItem(fileName: "a.md", text: "# Raft\n"))
    _ = try await host.run(DeleteItems([item.id]))
    await host.close()

    let again = try await LocalHost.start(root: place.root, database: place.database, environment: world.environment)

    #expect(try await again.run(RestoreDeleted()).isEmpty)
    #expect(try await again.listItems().isEmpty)
    #expect(place.store.setAsideItems().isEmpty)
    await again.close()
  }

  @Test func renamingKeepsEverythingElseAndRefusesAnEmptyTitle() async throws {
    try await withHost { host, _, _ in
      let item = try await host.run(AddTextItem(fileName: "a.md", text: "# Raft\n\nterm\n"))

      let renamed = try await host.run(RenameItem(item: item.id, title: "  Raft 共识  "))

      #expect(renamed.title == "Raft 共识")
      #expect(try await host.itemPage(item.id).item == renamed)
      #expect(try await host.run(ReadItemText(item: item.id)).contains("term"))
      await #expect(throws: HostError.self) { try await host.run(RenameItem(item: item.id, title: " ")) }
    }
  }

  @Test func aPictureBecomesTheCoverAndAnythingElseIsRefused() async throws {
    try await withHost { host, _, _ in
      let item = try await host.run(AddTextItem(fileName: "a.md", text: "# Raft\n"))
      let folder = FileManager.default.temporaryDirectory.appending(path: "loci-cover-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: folder) }
      let picture = folder.appending(path: "cover.png")
      try Data("png".utf8).write(to: picture)
      let text = folder.appending(path: "notes.txt")
      try Data("text".utf8).write(to: text)

      _ = try await host.run(SetCover(item: item.id, upload: try await host.upload(LocalFile(picture))))

      #expect(try await host.run(ReadCover(item: item.id)) == Data("png".utf8))
      let upload = try await host.upload(LocalFile(text))
      await #expect(throws: HostError.self) { try await host.run(SetCover(item: item.id, upload: upload)) }
    }
  }
}
