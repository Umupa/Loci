import Foundation
import LociModel
import Testing

@testable import LociHost

/// L-S9: what happens in the library shows in the main conversation where it happened.
@Suite(.timeLimit(.minutes(1)))
struct EventScenarioTests {
  private func events(_ conversation: Conversation) -> [WorldEvent.Kind] {
    conversation.entries.compactMap { entry in
      if case .event(let event) = entry { event.kind } else { nil }
    }
  }

  @Test func savingAndFinishingAnItemShowInTheMainConversationInOrder() async throws {
    try await withHost { host, _, world in
      _ = try await host.run(SendMessage(to: .main, text: "Hi"))
      _ = try #require(await settled(host))
      world.advance(minutes: 1)
      let item = try await host.run(AddTextItem(fileName: "raft.md", text: "# Raft\n\nterm\n"))
      _ = try await host.run(MarkRead(content: .item(item.id)))
      _ = try await host.run(MarkRead(content: .item(item.id)))

      let conversation = try await host.conversation(.main)

      #expect(events(conversation) == [.saved(item, job: nil), .finishedReading(item)])
      #expect(conversation.entries.prefix(2).allSatisfy { if case .message = $0 { true } else { false } })
    }
  }

  @Test func aLinkBeingFetchedShowsItsJob() async throws {
    try await withHost { host, _, _ in
      let feed = host.subscribe(OneConversation(.main))

      let item = try await host.run(AddLink(url: try #require(URL(string: "https://example.com/post"))))

      let shown = await value(feed) { conversation in
        conversation.entries.contains { entry in
          if case .event(let event) = entry, case .saved(let saved, let job) = event.kind {
            saved.id == item.id && job != nil
          } else {
            false
          }
        }
      }
      #expect(shown != nil)
    }
  }

  @Test func eventsAboutADeletedItemAreGone() async throws {
    try await withHost { host, _, _ in
      let item = try await host.run(AddTextItem(fileName: "raft.md", text: "# Raft\n\nterm\n"))

      _ = try await host.run(DeleteItem(item: item.id, notes: .delete))

      #expect(events(try await host.conversation(.main)).isEmpty)
    }
  }

  @Test func highlightsAreToldToLociButNotShown() async throws {
    try await withHost { host, _, world in
      _ = try await host.run(SendMessage(to: .main, text: "Hi"))
      _ = try #require(await settled(host))
      world.advance(minutes: 1)
      let item = try await host.run(AddTextItem(fileName: "raft.md", text: "# Raft\n\nterm and index\n"))
      _ = try await host.run(
        AddNote(locator: .item(item.id, .quote(try TextQuote("term"))), excerpt: "term and index"))

      _ = try await host.run(SendMessage(to: .main, text: "Again"))
      _ = try #require(await settled(host, prompts: 2))

      #expect(events(try await host.conversation(.main)) == [.saved(item, job: nil)])
      #expect(world.agent.prompts.last?.contains("highlighted in \"Raft\"") == true)
      #expect(world.agent.prompts.last?.contains(": \"term and index\"") == true)
    }
  }
}
