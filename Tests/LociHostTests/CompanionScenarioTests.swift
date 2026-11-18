import Foundation
import LociModel
import Testing

@testable import LociHost

/// L-S8: any item can be read with a mentor alongside, who can be changed midway; every answer is marked
/// with who gave it.
@Suite(.timeLimit(.minutes(1)))
struct CompanionScenarioTests {
  static var agent: FakeAgent {
    FakeAgent { prompt in
      if prompt.contains("new mentor") { return .reply("Ready.") }
      if prompt.contains("hang") { return .hang }
      return .reply("It filters, then scores.")
    }
  }

  struct Setup {
    let item: Item
    let ada: Mentor
    let alan: Mentor
  }

  static func setUp(_ host: LocalHost) async throws -> Setup {
    let item = try await host.run(AddTextItem(fileName: "s.md", text: "# Scheduling\n\nPods need a node.\n"))
    let ada = try await host.run(CreateMentor(request: "Scheduling"))
    let alan = try await host.run(CreateMentor(request: "Networking"))
    for mentor in [ada, alan] {
      _ = await value(host.subscribe(MentorConversation(mentor: mentor.id))) { $0.turn == nil && !$0.messages.isEmpty }
    }
    return Setup(item: item, ada: ada, alan: alan)
  }

  static func settled(_ host: LocalHost, on item: EntityID, questions: Int) async -> ItemConversation? {
    await value(host.subscribe(CompanionConversation(item: item))) { conversation in
      conversation.turn == nil
        && conversation.messages.count { if case .prompt = $0.message.body { true } else { false } } == questions
    }
  }

  @Test func anAnswerOnAnItemIsMarkedWithItsMentorAndStaysOutOfTheCourse() async throws {
    try await withHost(agent: Self.agent) { host, _, _ in
      let setup = try await Self.setUp(host)

      _ = try await host.run(AskCompanion(item: setup.item.id, mentor: setup.ada.id, text: "How does it pick?"))

      let done = try #require(await Self.settled(host, on: setup.item.id, questions: 1))
      #expect(done.messages.map(\.mentor) == [setup.ada.id, setup.ada.id])
      #expect(done.messages.last?.message.body == .reply("It filters, then scores."))
      #expect(done.companion == setup.ada.id)
      let course = try await host.conversation(of: setup.ada.id)
      #expect(!course.messages.contains { $0.body == .reply("It filters, then scores.") })
    }
  }

  @Test func theFirstQuestionTellsTheMentorWhereTheItemAndTheNotesAre() async throws {
    try await withHost(agent: Self.agent) { host, place, world in
      let setup = try await Self.setUp(host)
      let locator = Locator.item(setup.item.id, .quote(try TextQuote("Pods need")))
      _ = try await host.run(AddNote(locator: locator, excerpt: "Pods need a node.", thought: "Which node?"))

      _ = try await host.run(AskCompanion(item: setup.item.id, mentor: setup.ada.id, text: "How?"))
      _ = try #require(await Self.settled(host, on: setup.item.id, questions: 1))
      _ = try await host.run(AskCompanion(item: setup.item.id, mentor: setup.ada.id, text: "And then?"))
      _ = try #require(await Self.settled(host, on: setup.item.id, questions: 2))

      let files = try place.store.itemFiles(setup.item.id)
      let first = try #require(world.agent.prompts.dropLast().last)
      #expect(first.contains(try #require(files.content).path(percentEncoded: false)))
      #expect(first.contains(files.notes.path(percentEncoded: false)))
      #expect(first.contains("> Pods need a node.\n  My thought: Which node?"))
      #expect(first.hasSuffix("My question:\nHow?"))
      #expect(world.agent.prompts.last == "And then?")
      #expect(world.agent.opened.last?.workingDirectory == (try place.store.workingFolder(of: setup.ada.id)))
    }
  }

  @Test func changingTheMentorKeepsEarlierAnswersEachMarkedWithItsOwn() async throws {
    try await withHost(agent: Self.agent) { host, place, world in
      let setup = try await Self.setUp(host)

      _ = try await host.run(AskCompanion(item: setup.item.id, mentor: setup.ada.id, text: "One?"))
      _ = try #require(await Self.settled(host, on: setup.item.id, questions: 1))
      _ = try await host.run(AskCompanion(item: setup.item.id, mentor: setup.alan.id, text: "Two?"))

      let done = try #require(await Self.settled(host, on: setup.item.id, questions: 2))
      #expect(done.messages.map(\.mentor) == [setup.ada.id, setup.ada.id, setup.alan.id, setup.alan.id])
      #expect(done.companion == setup.alan.id)
      #expect(world.agent.prompts.last?.contains("read along") == true)
      #expect(world.agent.opened.last?.workingDirectory == (try place.store.workingFolder(of: setup.alan.id)))
    }
  }

  @Test func aMentorAskedAgainAfterARestartGoesOnInItsOwnSessionOnTheItem() async throws {
    let place = Place()
    defer { place.remove() }
    let world = TestWorld(agent: Self.agent)
    let first = try await LocalHost.start(root: place.root, database: place.database, environment: world.environment)
    let setup = try await Self.setUp(first)
    _ = try await first.run(AskCompanion(item: setup.item.id, mentor: setup.ada.id, text: "One?"))
    _ = try #require(await Self.settled(first, on: setup.item.id, questions: 1))
    let session = try #require(world.agent.opened.last)
    await first.close()

    let second = try await LocalHost.start(root: place.root, database: place.database, environment: world.environment)
    let before = try #require(await Self.settled(second, on: setup.item.id, questions: 1))
    #expect(before.companion == setup.ada.id)
    _ = try await second.run(AskCompanion(item: setup.item.id, mentor: setup.ada.id, text: "Two?"))
    let after = try #require(await Self.settled(second, on: setup.item.id, questions: 2))
    await second.close()

    #expect(before.messages.map(\.mentor) == [setup.ada.id, setup.ada.id])
    #expect(after.messages.count == 4)
    #expect(world.agent.opened.last?.resume?.value.hasPrefix("fake-") == true)
    #expect(world.agent.opened.last?.workingDirectory == session.workingDirectory)
    #expect(world.agent.prompts.last == "Two?")
  }

  @Test func theChosenCompanionIsRememberedAndOfferedOnOtherItems() async throws {
    try await withHost(agent: Self.agent) { host, _, _ in
      let setup = try await Self.setUp(host)
      let other = try await host.run(AddTextItem(fileName: "o.md", text: "# Other\n"))

      let chosen = try await host.run(ChooseCompanion(item: setup.item.id, mentor: setup.alan.id))

      #expect(chosen.companion == setup.alan.id)
      #expect(try await host.itemConversation(on: other.id).companion == setup.alan.id)
      _ = try await host.run(ChooseCompanion(item: other.id, mentor: setup.ada.id))
      #expect(try await host.itemConversation(on: setup.item.id).companion == setup.alan.id)
    }
  }

  @Test func withoutAChoiceTheFirstMentorReadsAlongAndWithoutMentorsNoneDoes() async throws {
    try await withHost(agent: Self.agent) { host, _, _ in
      let item = try await host.run(AddTextItem(fileName: "s.md", text: "# S\n"))
      #expect(try await host.itemConversation(on: item.id).companion == nil)
      let mentor = try await host.run(CreateMentor(request: "Scheduling"))
      #expect(try await host.itemConversation(on: item.id).companion == mentor.id)
    }
  }

  @Test func aQuestionWhileAnotherIsAnsweredOnTheItemIsRefusedUntilItStops() async throws {
    try await withHost(agent: Self.agent) { host, _, _ in
      let setup = try await Self.setUp(host)

      _ = try await host.run(AskCompanion(item: setup.item.id, mentor: setup.ada.id, text: "hang"))
      await #expect(throws: HostError.invalidRequest(MentorRun.busyOnItem)) {
        try await host.run(AskCompanion(item: setup.item.id, mentor: setup.alan.id, text: "Two?"))
      }
      _ = try await host.run(StopCompanion(item: setup.item.id))
      let stopped = try #require(await Self.settled(host, on: setup.item.id, questions: 1))
      #expect(stopped.messages.last?.message.body == .ended(.interrupted))

      _ = try await host.run(AskCompanion(item: setup.item.id, mentor: setup.alan.id, text: "Two?"))
      _ = try #require(await Self.settled(host, on: setup.item.id, questions: 2))
    }
  }

  @Test func aPassageQuestionOnAnItemIsSavedInItsHighlightWithTheMentor() async throws {
    try await withHost(agent: Self.agent) { host, place, world in
      let setup = try await Self.setUp(host)
      let passage = Passage(
        locator: .item(setup.item.id, .quote(try TextQuote("Pods need"))), excerpt: "Pods need a node.")

      _ = try await host.run(AskCompanion(item: setup.item.id, mentor: setup.alan.id, text: "Why?", passage: passage))

      let done = try #require(await Self.settled(host, on: setup.item.id, questions: 1))
      let note = try #require(place.store.notes(on: .item(setup.item.id)).value.first)
      #expect(note.excerpt == "Pods need a node.")
      #expect(note.exchanges.map(\.answer) == ["It filters, then scores."])
      #expect(note.exchanges.map(\.mentor) == [setup.alan.id])
      #expect(done.messages.last?.message.body == .savedToNote(note.id))
      #expect(world.agent.prompts.last?.hasSuffix("> Pods need a node.\n\nWhy?") == true)
    }
  }

  @Test func aPassageFromAnotherItemIsRefused() async throws {
    try await withHost(agent: Self.agent) { host, _, _ in
      let setup = try await Self.setUp(host)
      let elsewhere = try await host.run(AddTextItem(fileName: "o.md", text: "# Other\n"))
      let passage = Passage(locator: .item(elsewhere.id, .quote(try TextQuote("x"))), excerpt: "x")

      await #expect(throws: HostError.invalidRequest("the passage is not in this item")) {
        try await host.run(AskCompanion(item: setup.item.id, mentor: setup.ada.id, text: "Why?", passage: passage))
      }
    }
  }

  @Test func deletingAMentorKeepsItsAnswersOnItemsAndDeletingTheItemRemovesThem() async throws {
    try await withHost(agent: Self.agent) { host, _, _ in
      let setup = try await Self.setUp(host)
      _ = try await host.run(AskCompanion(item: setup.item.id, mentor: setup.ada.id, text: "One?"))
      _ = try #require(await Self.settled(host, on: setup.item.id, questions: 1))

      _ = try await host.run(DeleteMentor(mentor: setup.ada.id, notes: .keep))
      let kept = try await host.itemConversation(on: setup.item.id)
      #expect(kept.messages.map(\.mentor) == [setup.ada.id, setup.ada.id])
      #expect(kept.companion == setup.alan.id)

      _ = try await host.run(DeleteItem(item: setup.item.id, notes: .delete))
      await #expect(throws: HostError.self) { try await host.itemConversation(on: setup.item.id) }
      #expect(try host.database.messages(on: setup.item.id).isEmpty)
    }
  }

  @Test func aMentorWhoseAgentIsMissingStillGetsTheQuestionAndSaysWhy() async throws {
    try await withHost(agent: Self.agent) { host, place, _ in
      let setup = try await Self.setUp(host)
      try place.store.save(
        try Mentor(
          id: setup.ada.id, name: setup.ada.name, avatar: setup.ada.avatar, color: setup.ada.color, provider: .grok))

      _ = try await host.run(AskCompanion(item: setup.item.id, mentor: setup.ada.id, text: "One?"))

      let done = try #require(await Self.settled(host, on: setup.item.id, questions: 1))
      #expect(done.messages.last?.message.body == .ended(.failed("grok is not installed on this Mac.")))
    }
  }
}
