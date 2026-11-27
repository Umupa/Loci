import Foundation
import LociModel
import Testing

@testable import LociHost

/// L-S4: each item has a conversation of its own with Loci; nobody is chosen to read along.
@Suite(.timeLimit(.minutes(1)))
struct ItemConversationTests {
  static let article = "# How we built Pingora\n\nA connection pool inside one worker can't be reused by another.\n"

  private func article(_ host: LocalHost) async throws -> Item {
    try await host.run(AddTextItem(fileName: "pingora.md", text: Self.article))
  }

  private func passage(on item: Item) throws -> Passage {
    Passage(
      locator: .item(item.id, .quote(try TextQuote("can't be reused"))), excerpt: "can't be reused by another")
  }

  @Test func theFirstMessageOnAnItemTellsLociWhatItIsAndWhereItsTextIs() async throws {
    try await withHost { host, _, world in
      let item = try await article(host)

      _ = try await host.run(SendMessage(to: .item(item.id), text: "Why?"))
      _ = try #require(await settled(host, .item(item.id)))
      _ = try await host.run(SendMessage(to: .item(item.id), text: "And?"))
      _ = try #require(await settled(host, .item(item.id), prompts: 2))

      let first = try #require(world.agent.prompts.first)
      #expect(first.contains("\"How we built Pingora\" (an article)"))
      #expect(first.contains("../library/"))
      #expect(first.contains("Tag your notes [library/\(item.id)]"))
      #expect(first.hasSuffix("Why?"))
      #expect(world.agent.prompts.last?.contains("\"How we built Pingora\" (an article)") == false)
    }
  }

  /// I-S4: the conversation on an item is told why the person took it in.
  @Test func theFirstMessageOnAnItemSaysWhyItWasTakenIn() async throws {
    try await withHost { host, place, world in
      let item = try await article(host)
      try place.store.save(
        try Item(id: item.id, kind: item.kind, title: item.title, why: "To compare it with what we run at work."))

      _ = try await host.run(SendMessage(to: .item(item.id), text: "Why?"))
      _ = try #require(await settled(host, .item(item.id)))

      let first = try #require(world.agent.prompts.first)
      #expect(first.contains("Why they took it in, in their words: To compare it with what we run at work."))
    }
  }

  @Test func askingAboutAPassageSavesTheAnswerInItsHighlight() async throws {
    try await withHost(agent: FakeAgent { _ in .reply("A worker is a process.") }) { host, place, world in
      let item = try await article(host)
      let passage = try passage(on: item)

      _ = try await host.run(SendMessage(to: .item(item.id), text: " Why? ", passage: passage))

      let done = try #require(await settled(host, .item(item.id)))
      let note = try #require(place.store.notes(on: .item(item.id)).value.first)
      #expect(note.excerpt == "can't be reused by another")
      #expect(note.exchanges.map(\.question) == ["Why?"])
      #expect(note.exchanges.map(\.answer) == ["A worker is a process."])
      #expect(done.messages.last?.body == .savedToNote(note.id))
      #expect(
        done.messages.first?.body
          == .prompt(
            Prompt(
              text: "Why?", purpose: .chat,
              passage: QuotedPassage(locator: passage.locator, excerpt: passage.excerpt, note: note.id))))
      #expect(world.agent.prompts.last?.contains("> can't be reused by another") == true)
    }
  }

  /// HL-S6: the thought on the whole item is in what a new session on it is told.
  @Test func theFirstMessageOnAnItemCarriesTheThoughtOnTheWhole() async throws {
    try await withHost { host, _, world in
      let item = try await article(host)
      _ = try await host.run(SetWholeThought(item: item.id, thought: "Pools per worker are the real cost."))

      _ = try await host.run(SendMessage(to: .item(item.id), text: "Why?"))
      _ = try #require(await settled(host, .item(item.id)))

      let first = try #require(world.agent.prompts.first)
      #expect(first.contains("Their thought on the whole item: Pools per worker are the real cost."))
      #expect(!first.contains("> (a place)"))
    }
  }

  /// HL-S3: asking about a picture tells Loci where the picture is, so it can look at it.
  @Test func askingAboutAPictureTellsLociWhereThePictureIs() async throws {
    try await withHost { host, place, world in
      let item = try await article(host)
      let passage = Passage(
        locator: .item(item.id, .quote(try TextQuote("worker"))), excerpt: "", pictures: ["images/pool.png"])

      _ = try await host.run(SendMessage(to: .item(item.id), text: "What does this show?", passage: passage))
      _ = try #require(await settled(host, .item(item.id)))

      let sent = try #require(world.agent.prompts.last)
      let folder = try place.store.itemFolder(item.id).lastPathComponent
      #expect(sent.contains("../library/\(folder)/images/pool.png"))
      let note = try #require(place.store.notes(on: .item(item.id)).value.first)
      #expect(note.pictures == ["images/pool.png"])
      #expect(note.excerpt == nil)
    }
  }

  @Test func askingAgainAboutTheSamePassageAddsToTheSameHighlight() async throws {
    try await withHost { host, place, _ in
      let item = try await article(host)
      let passage = try passage(on: item)
      let highlight = try await host.run(AddNote(locator: passage.locator, excerpt: passage.excerpt, thought: "Hm"))

      _ = try await host.run(SendMessage(to: .item(item.id), text: "Why?", passage: passage))
      _ = try #require(await settled(host, .item(item.id)))
      _ = try await host.run(SendMessage(to: .item(item.id), text: "And then?", passage: passage))
      _ = try #require(await settled(host, .item(item.id), prompts: 2))

      let notes = place.store.notes(on: .item(item.id)).value
      #expect(notes.map(\.id) == [highlight.id])
      #expect(notes.first?.thought == "Hm")
      #expect(notes.first?.exchanges.map(\.question) == ["Why?", "And then?"])
    }
  }

  @Test func aPassageFromElsewhereIsRefused() async throws {
    try await withHost { host, _, world in
      let item = try await article(host)
      let elsewhere = Passage(locator: .item(world.nextID(), .quote(try TextQuote("x"))), excerpt: "x")

      await #expect(throws: HostError.self) {
        try await host.run(SendMessage(to: .item(item.id), text: "Why?", passage: elsewhere))
      }
      await #expect(throws: HostError.self) {
        try await host.run(SendMessage(to: .main, text: "Why?", passage: try passage(on: item)))
      }
    }
  }

  @Test func theMainConversationAndAnItemsAnswerAtTheSameTime() async throws {
    try await withHost(agent: FakeAgent { _ in .hang }) { host, _, _ in
      let item = try await article(host)

      _ = try await host.run(SendMessage(to: .main, text: "Hi"))
      _ = try await host.run(SendMessage(to: .item(item.id), text: "Hi"))

      #expect(await host.lociStatus() == LociStatus(work: .answering(nil)))
      await #expect(throws: HostError.self) { try await host.run(SendMessage(to: .main, text: "Again")) }
      _ = try await host.run(StopTurn(in: .main))
      _ = try await host.run(StopTurn(in: .item(item.id)))
      #expect(await host.lociStatus() == LociStatus(work: nil))
    }
  }

  @Test func anItemsConversationGoesWithTheItem() async throws {
    try await withHost { host, _, _ in
      let item = try await article(host)
      _ = try await host.run(SendMessage(to: .item(item.id), text: "Why?"))
      _ = try #require(await settled(host, .item(item.id)))

      _ = try await host.run(DeleteItems([item.id]))

      await #expect(throws: HostError.notFound(item.id.description)) { try await host.conversation(.item(item.id)) }
      #expect(try !host.database.messages(of: .conversation(.item(item.id))).isEmpty)

      let other = try await host.run(AddTextItem(fileName: "b.md", text: "# B\n"))
      _ = try await host.run(DeleteItems([other.id]))

      #expect(try host.database.messages(of: .conversation(.item(item.id))).isEmpty)
    }
  }

  @Test func thereIsNoConversationOnAnItemThatIsNotThere() async throws {
    try await withHost { host, _, world in
      await #expect(throws: HostError.self) { try await host.conversation(.item(world.nextID())) }
    }
  }

  /// C-13: starting over on an item keeps what was said there, and the next question goes to a fresh
  /// session that is told about the item again.
  @Test func startingOverOnAnItemKeepsItsMessagesAndTheNextQuestionGoesToAFreshSession() async throws {
    try await withHost { host, _, world in
      let item = try await article(host)
      _ = try await host.run(SendMessage(to: .item(item.id), text: "One?"))
      let before = try #require(await settled(host, .item(item.id)))
      let opened = world.agent.opened.count

      _ = try await host.run(StartOver(in: .item(item.id)))
      _ = try await host.run(SendMessage(to: .item(item.id), text: "Two?"))

      let done = try #require(await settled(host, .item(item.id), prompts: 2))
      #expect(Array(done.messages.prefix(before.messages.count)) == before.messages)
      #expect(done.messages[before.messages.count].body == .startedOver)
      #expect(world.agent.opened.count == opened + 1)
      #expect(world.agent.opened.last?.resume == nil)
      #expect(world.agent.prompts.last?.contains("\"How we built Pingora\" (an article)") == true)
      #expect(world.agent.prompts.last?.contains("One?") == false)
    }
  }

  @Test func anItemThatStartedOverStartsFreshAfterARestart() async throws {
    let place = Place()
    defer { place.remove() }
    let world = TestWorld()
    let first = try await LocalHost.start(root: place.root, database: place.database, environment: world.environment)
    let item = try await article(first)
    _ = try await first.run(SendMessage(to: .item(item.id), text: "One?"))
    _ = try #require(await settled(first, .item(item.id)))
    _ = try await first.run(StartOver(in: .item(item.id)))
    await first.close()

    let second = try await LocalHost.start(root: place.root, database: place.database, environment: world.environment)
    _ = try await second.run(SendMessage(to: .item(item.id), text: "Two?"))
    _ = try #require(await settled(second, .item(item.id), prompts: 2))
    await second.close()

    #expect(world.agent.opened.last?.resume == nil)
  }

  @Test func startingOverWhileLociAnswersOnTheItemIsRefused() async throws {
    try await withHost(agent: FakeAgent { _ in .hang }) { host, _, _ in
      let item = try await article(host)
      _ = try await host.run(SendMessage(to: .item(item.id), text: "hang"))

      await #expect(throws: HostError.invalidRequest(AgentRun.busy)) {
        try await host.run(StartOver(in: .item(item.id)))
      }
      _ = try await host.run(StopTurn(in: .item(item.id)))
    }
  }

  @Test func aQuestionLociCouldNotStartOnLeavesTheHighlightWithoutAnAnswer() async throws {
    try await withHost { host, place, _ in
      let item = try await article(host)
      _ = try await host.run(SetConversationRuntime(Runtime(provider: .grok), for: .item(item.id)))

      _ = try await host.run(SendMessage(to: .item(item.id), text: "Why?", passage: try passage(on: item)))

      let done = try #require(await settled(host, .item(item.id)))
      #expect(done.messages.last?.body == .ended(.unstarted(.grok, .notInstalled)))
      #expect(place.store.notes(on: .item(item.id)).value.first?.exchanges.isEmpty == true)
    }
  }
}
