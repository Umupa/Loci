import Foundation
import LociAgents
import LociModel
import Synchronization
import Testing

@testable import LociHost

@Suite(.timeLimit(.minutes(1)))
struct ConversationScenarioTests {
  /// L-S1: the reply arrives in pieces into one message, and the main conversation keeps it.
  @Test func aReplyStreamsIntoTheMainConversation() async throws {
    try await withManualHost { host, _, _, agent in
      let feed = host.subscribe(OneConversation(.main))
      _ = try await host.run(SendMessage(to: .main, text: "在吗"))
      #expect(await working(host))
      let session = try #require(await agent.sessions.last)

      await session.emit(.text(", hello"))
      let partial = await value(feed) { conversation in
        conversation.turn?.messages.contains { $0.body == .reply("Waiting, hello") } == true
      }
      await session.emit(.text(" there."))
      await session.finish()

      #expect(partial != nil)
      let done = await settled(host)
      #expect(done?.bodies == [.prompt(Prompt(text: "在吗", purpose: .chat)), .reply("Waiting, hello there.")])
    }
  }

  /// PERF-S1: a reply streaming in a word at a time reaches the window a few words at a time.
  @Test func aReplyStreamingAWordAtATimeIsShownAFewWordsAtATime() async throws {
    try await withManualHost { host, _, _, agent in
      let feed = host.subscribe(OneConversation(.main))
      _ = try await host.run(SendMessage(to: .main, text: "Hi"))
      #expect(await working(host))
      let session = try #require(await agent.sessions.last)
      let words = (1...40).map { "w\($0) " }

      for word in words { await session.emit(.text(word)) }

      let shown = Shown()
      let whole = await value(feed) { conversation in
        let reply = conversation.turn?.messages.compactMap { if case .reply(let text) = $0.body { text } else { nil } }
        if let reply = reply?.last { shown.add(reply) }
        return reply?.last == "Waiting" + words.joined()
      }
      #expect(whole != nil)
      #expect(shown.count < words.count / 4)
      await session.finish()
    }
  }

  @Test func aMessageWhileLociAnswersThereIsRefused() async throws {
    try await withHost(agent: FakeAgent { _ in .hang }) { host, _, _ in
      _ = try await host.run(SendMessage(to: .main, text: "Hi"))

      await #expect(throws: HostError.self) { try await host.run(SendMessage(to: .main, text: "Hi")) }
      _ = try await host.run(StopTurn(in: .main))
    }
  }

  @Test func anEmptyMessageIsRefused() async throws {
    try await withHost { host, _, _ in
      await #expect(throws: HostError.self) { try await host.run(SendMessage(to: .main, text: "  \n")) }
    }
  }

  /// Every session runs with full access; an agent that still asks is allowed, and nothing waits on the
  /// person.
  @Test func aCommandTheAgentAsksAboutRunsWithoutAsking() async throws {
    try await withHost(agent: FakeAgent { _ in .askToRun }) { host, _, _ in
      _ = try await host.run(SendMessage(to: .main, text: "Run it"))

      let done = try #require(await settled(host))
      let tool = done.messages.compactMap { if case .tool(let tool) = $0.body { tool } else { nil } }.last
      #expect(tool?.state == .succeeded)
      #expect(done.bodies.last == .reply("It printed hi."))
    }
  }

  /// What the agent says about its context window is in the conversation.
  @Test func theContextUsageTheAgentReportsIsShown() async throws {
    try await withManualHost { host, _, _, agent in
      _ = try await host.run(SendMessage(to: .main, text: "Hi"))
      #expect(await working(host))
      let session = try #require(await agent.sessions.last)

      await session.emit(.context(ContextUsage(used: 68_000, window: 200_000)))

      let reported = await value(host.subscribe(OneConversation(.main))) { $0.context != nil }
      #expect(reported?.context == ContextUsage(used: 68_000, window: 200_000))
      await session.finish()
    }
  }

  /// Stopping ends the turn, and the conversation goes on.
  @Test func stoppingEndsTheTurnAndTheConversationGoesOn() async throws {
    let agent = FakeAgent { prompt in prompt.typed == "Take your time" ? .hang : .reply("Ready.") }
    try await withHost(agent: agent) { host, _, _ in
      _ = try await host.run(SendMessage(to: .main, text: "Take your time"))

      _ = try await host.run(StopTurn(in: .main))

      #expect(await settled(host)?.bodies.last == .ended(.interrupted))
      _ = try await host.run(SendMessage(to: .main, text: "Again"))
      #expect(await settled(host, prompts: 2)?.bodies.last == .reply("Ready."))
    }
  }

  /// After a restart the conversation is all there, and the agent's session is resumed.
  @Test func theConversationSurvivesARestart() async throws {
    let place = Place()
    defer { place.remove() }
    let agent = FakeAgent { _ in .reply("Ready.") }
    let world = TestWorld(agent: agent)
    let first = try await LocalHost.start(root: place.root, database: place.database, environment: world.environment)
    _ = try await first.run(SendMessage(to: .main, text: "Hi"))
    let before = await settled(first)
    await first.close()

    let second = try await LocalHost.start(root: place.root, database: place.database, environment: world.environment)
    let after = try await second.conversation(.main)
    _ = try await second.run(SendMessage(to: .main, text: "Still there?"))
    _ = try #require(await settled(second, prompts: 2))
    await second.close()

    #expect(after.messages == before?.messages)
    #expect(agent.opened.last?.resume?.value == "fake-1")
  }

  /// L-S2: `/new` keeps every message, leaves a line, and the next message goes to a session that is told
  /// nothing of what was said before.
  @Test func startingOverKeepsTheMessagesAndTheNextSessionStartsClean() async throws {
    let agent = FakeAgent { _ in .reply("Ready.") }
    try await withHost(agent: agent) { host, _, _ in
      _ = try await host.run(SendMessage(to: .main, text: "Remember the word cobalt"))
      let before = try #require(await settled(host))

      _ = try await host.run(StartOver(in: .main))
      _ = try await host.run(SendMessage(to: .main, text: "Again"))

      let after = try #require(await settled(host, prompts: 2))
      #expect(Array(after.messages.prefix(before.messages.count)) == before.messages)
      #expect(after.messages[before.messages.count].body == .startedOver)
      #expect(agent.opened.count == 2)
      #expect(agent.opened.last?.resume == nil)
      #expect(agent.prompts.last?.contains("cobalt") == false)
    }
  }

  @Test func aConversationThatStartedOverStartsFreshAfterARestart() async throws {
    let place = Place()
    defer { place.remove() }
    let agent = FakeAgent { _ in .reply("Ready.") }
    let world = TestWorld(agent: agent)
    let first = try await LocalHost.start(root: place.root, database: place.database, environment: world.environment)
    _ = try await first.run(SendMessage(to: .main, text: "Hi"))
    _ = await settled(first)
    _ = try await first.run(StartOver(in: .main))
    await first.close()

    let second = try await LocalHost.start(root: place.root, database: place.database, environment: world.environment)
    _ = try await second.run(SendMessage(to: .main, text: "Still there?"))
    let after = try #require(await settled(second, prompts: 2))
    await second.close()

    #expect(after.messages.contains { $0.body == .startedOver })
    #expect(agent.opened.last?.resume == nil)
  }

  @Test func startingOverTwiceOrOnNothingLeavesAtMostOneLine() async throws {
    try await withHost { host, _, _ in
      _ = try await host.run(StartOver(in: .main))
      #expect(try await host.conversation(.main).entries.isEmpty)
      _ = try await host.run(SendMessage(to: .main, text: "Hi"))
      _ = await settled(host)

      _ = try await host.run(StartOver(in: .main))
      _ = try await host.run(StartOver(in: .main))

      #expect(try await host.conversation(.main).messages.count { $0.body == .startedOver } == 1)
    }
  }

  @Test func startingOverWhileLociAnswersIsRefused() async throws {
    try await withHost(agent: FakeAgent { _ in .hang }) { host, _, _ in
      _ = try await host.run(SendMessage(to: .main, text: "Hi"))

      await #expect(throws: HostError.self) { try await host.run(StartOver(in: .main)) }
      _ = try await host.run(StopTurn(in: .main))
    }
  }

  @Test func aRuntimeThatIsNotInstalledSaysSo() async throws {
    try await withHost { host, _, _ in
      _ = try await host.run(SetRuntime(Runtime(provider: .grok)))

      _ = try await host.run(SendMessage(to: .main, text: "Hi"))

      #expect(await settled(host)?.bodies.last == .ended(.unstarted(.grok, .notInstalled)))
    }
  }

  /// C-12: an agent that would not start says whether it is not installed or is there and would not run.
  @Test func anAgentThatWouldNotStartSaysWhy() async throws {
    for (failure, said) in [
      (AgentError.wouldNotStart, AgentStartFailure.wouldNotStart),
      (.cannotLaunch("The file “codex” doesn’t exist."), .notInstalled),
    ] {
      try await withManualHost(agent: ManualAgent(openingFailure: failure)) { host, _, _, _ in
        _ = try await host.run(SendMessage(to: .main, text: "Hi"))

        #expect(await settled(host)?.bodies.last == .ended(.unstarted(.pi, said)))
      }
    }
  }

  /// Every session works in Loci's folder, which holds the instructions it reads.
  @Test func sessionsWorkInLocisFolderUnderItsInstructions() async throws {
    let agent = FakeAgent { _ in .reply("Ready.") }
    try await withHost(agent: agent) { host, place, _ in
      _ = try await host.run(SendMessage(to: .main, text: "Hi"))
      _ = await settled(host)

      let folder = place.root.appending(path: "agent")
      #expect(agent.opened.first?.workingDirectory.standardizedFileURL == folder.standardizedFileURL)
      let instructions = try String(contentsOf: folder.appending(path: "AGENTS.md"), encoding: .utf8)
      #expect(instructions.contains("# How Loci works"))
      #expect(instructions.contains("You are Loci."))
      #expect(instructions.contains("# The person (USER.md)"))
    }
  }

  /// What was said is copied, as text, where Loci can search it.
  @Test func eachTurnIsCopiedIntoLocisConversations() async throws {
    try await withHost { host, place, _ in
      _ = try await host.run(SendMessage(to: .main, text: "我上次说了什么"))
      _ = await settled(host)

      let day = place.root.appending(path: "agent/conversations/2025-11-17")
      let copies = try FileManager.default.contentsOfDirectory(at: day, includingPropertiesForKeys: nil)
      #expect(copies.count == 1)
      let text = try String(contentsOf: try #require(copies.first), encoding: .utf8)
      #expect(text.contains("我上次说了什么") && text.contains("Hello there."))
      #expect(!text.contains("loci-context"))
    }
  }
}

/// The replies a subscriber was shown, counted.
private final class Shown: Sendable {
  private let replies = Mutex<Set<String>>([])

  func add(_ reply: String) { replies.withLock { _ = $0.insert(reply) } }
  var count: Int { replies.withLock(\.count) }
}
