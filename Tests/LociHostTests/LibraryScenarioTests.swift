import Foundation
import LociModel
import Testing

@testable import LociHost
@testable import LociStore

struct LibraryScenarioTests {
  /// α1-S3: a text file becomes an item that can be read in full.
  @Test func aTextFileBecomesAnItemToRead() async throws {
    try await withHost { host, _, _ in
      let items = host.subscribe(AllItems())
      let text = "# Large-scale cluster management at Google with Borg\n\nBorg admits, schedules, starts…\n"
      let item = try await host.run(AddTextItem(fileName: "borg.md", text: text))

      #expect(item.title == "Large-scale cluster management at Google with Borg")
      #expect(item.kind == .article)
      let listed = await value(items) { $0 == [item] }
      #expect(listed != nil)
      #expect(try await host.run(ReadItemText(item: item.id)) == text)
    }
  }

  @Test func withoutAHeadingTheFileNameIsTheTitle() async throws {
    try await withHost { host, _, _ in
      let named = try await host.run(AddTextItem(fileName: "调度笔记.txt", text: "没有标题"))
      let dotted = try await host.run(AddTextItem(fileName: "notes.v2.md", text: ""))

      #expect(named.title == "调度笔记")
      #expect(dotted.title == "notes.v2")
      await #expect(throws: HostError.self) { try await host.run(AddTextItem(fileName: "", text: "no heading")) }
    }
  }

  @Test func deletingAnItemEmptiesItsPage() async throws {
    try await withHost { host, _, _ in
      let item = try await host.run(AddTextItem(fileName: "a.md", text: "text"))
      let items = host.subscribe(AllItems())
      let listed = await value(items) { $0 == [item] }
      #expect(listed != nil)

      _ = try await host.run(DeleteItem(item: item.id, notes: .delete))

      let emptied = await value(items) { $0.isEmpty }
      #expect(emptied != nil)
      await #expect(throws: HostError.notFound(item.id.description)) {
        try await host.run(ReadItemText(item: item.id))
      }
    }
  }

  @Test func searchAndReadingStateGoThroughTheHost() async throws {
    try await withHost { host, _, world in
      let item = try await host.run(AddTextItem(fileName: "a.md", text: "# 调度器\n\n过滤与打分\n"))
      let content = ContentRef.item(item.id)
      let position = Locator.item(item.id, .quote(try TextQuote("打分")))

      let hits = try await host.run(Search(text: "调度"))

      #expect(Set(hits.map(\.target)) == [.item(item.id)])
      #expect(Set(hits.map(\.field)) == [.title, .body])
      #expect(try await host.run(ReadReadingState(content: content)) == nil)
      _ = try await host.run(SaveReadingPosition(content: content, position: position))
      #expect(try await host.run(ReadReadingState(content: content))?.position == position)
      await #expect(throws: HostError.self) {
        try await host.run(SaveReadingPosition(content: .item(world.nextID()), position: position))
      }
    }
  }

  @Test func contentReadToTheEndStaysReadWhenTheReaderGoesBackUp() async throws {
    try await withHost { host, _, _ in
      let item = try await host.run(AddTextItem(fileName: "a.md", text: "# 调度器\n\n过滤与打分\n"))
      let content = ContentRef.item(item.id)
      let top = Locator.item(item.id, .quote(try TextQuote("调度器")))

      _ = try await host.run(MarkRead(content: content))
      _ = try await host.run(SaveReadingPosition(content: content, position: top))

      let state = try await host.run(ReadReadingState(content: content))
      #expect(state?.finished == true)
      #expect(state?.position == top)
      #expect(state?.updatedAt == TestWorld.instant)
    }
  }
}
