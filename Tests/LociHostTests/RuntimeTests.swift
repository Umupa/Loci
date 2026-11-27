import Foundation
import LociModel
import Testing

@testable import LociHost

/// L-S6, L-S26: each conversation keeps what it runs on; a new one starts on what the last of its kind chose.
@Suite(.timeLimit(.minutes(1)))
struct RuntimeTests {
  private static var agent: FakeAgent { FakeAgent(provider: .codex) }

  private func article(_ host: LocalHost, _ name: String) async throws -> ConversationRef {
    .item(try await host.run(AddTextItem(fileName: "\(name).md", text: "# \(name)\n")).id)
  }

  private func say(_ text: String, in conversation: ConversationRef, on host: LocalHost, prompts: Int = 1)
    async throws
  {
    _ = try await host.run(SendMessage(to: conversation, text: text))
    _ = try #require(await settled(host, conversation, prompts: prompts))
  }

  @Test func theSettingsSeeWhichAgentsAreInstalled() async throws {
    try await withHost { host, _, world in
      let found = try await host.run(DetectAgents())
      _ = try await host.run(DetectAgents(again: true))

      #expect(found == TestWorld.installed)
      #expect(world.lookedAgain == [false, true])
    }
  }

  @Test func withNothingEverChosenAConversationRunsOnWhatTheHostStartedWith() async throws {
    try await withHost(agent: Self.agent) { host, _, _ in
      let item = try await article(host, "raft")

      #expect(try await host.run(ReadConversationRuntime(.main)) == Runtime(provider: .codex))
      #expect(try await host.run(ReadConversationRuntime(item)) == Runtime(provider: .codex))
    }
  }

  @Test func aRuntimeChosenInOneConversationIsAnnouncedAndLeavesOtherKindsAlone() async throws {
    try await withHost(agent: Self.agent) { host, _, _ in
      let item = try await article(host, "raft")
      let feed = host.subscribe(ConversationRuntime(.main))
      let chosen = Runtime(provider: .codex, model: "gpt-5", effort: .high)

      _ = try await host.run(SetConversationRuntime(chosen, for: .main))

      #expect(await value(feed) { $0 == chosen } == chosen)
      #expect(try await host.run(ReadConversationRuntime(.main)) == chosen)
      #expect(try await host.run(ReadConversationRuntime(item)) == Runtime(provider: .codex))
    }
  }

  @Test func aNewConversationStartsOnWhatTheLastOfItsKindChose() async throws {
    try await withHost(agent: Self.agent) { host, _, _ in
      let raft = try await article(host, "raft")
      let paxos = try await article(host, "paxos")

      _ = try await host.run(SetConversationRuntime(Runtime(provider: .codex, model: "reading"), for: raft))

      #expect(try await host.run(ReadConversationRuntime(paxos)) == Runtime(provider: .codex, model: "reading"))
      #expect(try await host.run(ReadConversationRuntime(.main)) == Runtime(provider: .codex))
      #expect(try await host.run(ReadConversationRuntime(.course(EntityID()))) == Runtime(provider: .codex))
    }
  }

  @Test func aConversationKeepsItsRuntimeAfterAnotherOfItsKindChanges() async throws {
    try await withHost(agent: Self.agent) { host, _, world in
      let raft = try await article(host, "raft")
      let paxos = try await article(host, "paxos")
      try await say("Why?", in: raft, on: host)

      _ = try await host.run(SetConversationRuntime(Runtime(provider: .codex, model: "reading"), for: paxos))
      try await say("And?", in: raft, on: host, prompts: 2)
      try await say("Why?", in: paxos, on: host)

      #expect(world.agent.opened.map(\.model) == [nil, "reading"])
      #expect(try await host.run(ReadConversationRuntime(raft)) == Runtime(provider: .codex))
    }
  }

  @Test func theNextTurnRunsWithTheChosenModelAndEffort() async throws {
    try await withHost(agent: Self.agent) { host, _, world in
      _ = try await host.run(
        SetConversationRuntime(Runtime(provider: .codex, model: "gpt-5", effort: .high), for: .main))

      try await say("Hi", in: .main, on: host)

      #expect(world.agent.opened.last?.model == "gpt-5")
      #expect(world.agent.opened.last?.effort == .high)
    }
  }

  @Test func anUpgradeKeepsTheOneRuntimeOfBeforeForEveryKindOfConversation() async throws {
    let place = Place()
    defer { place.remove() }
    try FileManager.default.createDirectory(at: place.root, withIntermediateDirectories: true)
    try Data(#"{"runtime":{"provider":"codex","model":"old-model"}}"#.utf8).write(
      to: place.root.appending(path: "settings.json"))
    let world = TestWorld(agent: Self.agent)
    let host = try await LocalHost.start(root: place.root, database: place.database, environment: world.environment)
    let item = try await article(host, "raft")

    let old = Runtime(provider: .codex, model: "old-model")
    #expect(try await host.run(ReadConversationRuntime(.main)) == old)
    #expect(try await host.run(ReadConversationRuntime(item)) == old)
    #expect(try await host.run(ReadConversationRuntime(.project(EntityID()))) == old)
    await host.close()
  }

  @Test func theDataLocationIsTheHostsFolder() async throws {
    try await withHost { host, place, _ in
      let location = try await host.run(DataLocation())

      #expect(location == HostPath(place.root))
      #expect(await host.localFile(.dataFolder) == LocalFile(place.root))
    }
  }
}

/// L-S25: what talks in the background runs on the conversation it belongs to; panels and schedules on the tool
/// model.
struct ModelWorkTests {

  @Test func whatTalksRunsOnTheConversationItBelongsTo() {
    let (course, item, project) = (EntityID(), EntityID(), EntityID())
    #expect(ModelWork.Session.turn(.course(course)).runsOn == .conversation(.course(course)))
    #expect(ModelWork.Session.followUp(setIn: .item(item)).runsOn == .conversation(.item(item)))
    #expect(ModelWork.Session.repair(SourceKey(.project(project), "etf")).runsOn == .conversation(.project(project)))
    #expect(ModelWork.Session.repair(SourceKey(.chat, "etf")).runsOn == .conversation(.main))
    #expect(ModelWork.Session.review(.chat).runsOn == .conversation(.main))
    #expect(ModelWork.Session.review(.project(project)).runsOn == .conversation(.project(project)))
    #expect(ModelWork.Session.refresh.runsOn == .toolModel)
  }

  @Test func whatDoesNotTalkUsesTheToolModelAndTranslationItsOwn() {
    #expect(ModelWork.Request.translation.model == .translation)
    for request in [ModelWork.Request.chapters, .keyPoints, .tidying, .speakerNames] {
      #expect(request.model == .tool)
    }
  }
}
