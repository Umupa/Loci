import Foundation
import LociModel
import Testing

@testable import LociHost

@Suite(.timeLimit(.minutes(1)))
struct EventScenarioTests {
  @Test func savingReadingAndHighlightingGiveLociContextWithoutAddingChatEntries() async throws {
    try await withHost { host, _, world in
      _ = try await host.run(SendMessage(to: .main, text: "Hi"))
      let first = try #require(await settled(host))
      world.advance(minutes: 1)
      let item = try await host.run(AddTextItem(fileName: "raft.md", text: "# Raft\n\nterm and index\n"))
      _ = try await host.run(MarkRead(content: .item(item.id)))
      _ = try await host.run(MarkRead(content: .item(item.id)))
      _ = try await host.run(
        AddNote(locator: .item(item.id, .quote(try TextQuote("term"))), excerpt: "term and index"))

      #expect(try await host.conversation(.main).entries == first.entries)
      _ = try await host.run(SendMessage(to: .main, text: "Again"))
      let second = try #require(await settled(host, prompts: 2))

      let sent = try #require(world.agent.prompts.last)
      #expect(sent.contains("saved an article \"Raft\""))
      #expect(sent.components(separatedBy: "finished reading \"Raft\"").count == 2)
      #expect(sent.contains("highlighted in \"Raft\" (library/\(item.id)): \"term and index\""))
      #expect(second.bodies.contains(.prompt(Prompt(text: "Again", purpose: .chat))))
    }
  }

  @Test func aLinkBeingFetchedDoesNotPostInTheMainConversation() async throws {
    try await withHost { host, _, _ in
      _ = try await host.run(AddLink(url: try #require(URL(string: "https://example.com/post"))))
      #expect(try await host.conversation(.main).entries.isEmpty)
    }
  }

  @Test func lociIsNotToldAboutAnItemThatHasBeenDeleted() async throws {
    try await withHost { host, _, world in
      let item = try await host.run(AddTextItem(fileName: "raft.md", text: "# Raft\n\nterm\n"))
      _ = try await host.run(DeleteItems([item.id]))
      _ = try await host.run(SendMessage(to: .main, text: "Hi"))
      _ = try #require(await settled(host))
      let sent = try #require(world.agent.prompts.last)
      #expect(!sent.contains(item.id.description))
    }
  }
}
