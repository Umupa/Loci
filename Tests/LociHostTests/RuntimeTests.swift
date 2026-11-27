import Foundation
import LociModel
import LociStore
import Testing

@testable import LociHost

/// L-S6, L-S26: conversations run on their kind's default unless they chose their own.
@Suite(.timeLimit(.minutes(1)))
struct RuntimeTests {
  private static var agent: FakeAgent { FakeAgent(provider: .codex) }
  private static let reading = Runtime(provider: .codex, model: "reading")

  private func article(_ host: LocalHost, _ name: String) async throws -> ConversationRef {
    .item(try await host.run(AddTextItem(fileName: "\(name).md", text: "# \(name)\n")).id)
  }

  private func say(_ text: String, in conversation: ConversationRef, on host: LocalHost, prompts: Int = 1)
    async throws
  {
    _ = try await host.run(SendMessage(to: conversation, text: text))
    _ = try #require(await settled(host, conversation, prompts: prompts))
  }

  private func use(_ conversation: ConversationRef, on host: LocalHost) async throws -> RuntimeInUse {
    try await ConversationRuntime(conversation).value(from: host)
  }

  @Test func theSettingsSeeWhichAgentsAreInstalled() async throws {
    try await withHost { host, _, world in
      let found = try await host.run(DetectAgents())
      _ = try await host.run(DetectAgents(again: true))

      #expect(found == TestWorld.installed)
      #expect(world.lookedAgain.prefix(1) == [false])
      #expect(world.lookedAgain.contains(true))
    }
  }

  @Test func withNothingEverChosenAConversationRunsOnWhatTheHostStartedWith() async throws {
    try await withHost(agent: Self.agent) { host, _, _ in
      let item = try await article(host, "raft")

      #expect(try await host.run(ReadConversationRuntime(.main)) == Runtime(provider: .codex))
      #expect(try await host.run(ReadConversationRuntime(item)) == Runtime(provider: .codex))
    }
  }

  @Test func whatTheMainConversationChoosesIsItsKindsDefaultAndIsAnnounced() async throws {
    try await withHost(agent: Self.agent) { host, _, _ in
      let item = try await article(host, "raft")
      let feed = host.subscribe(ConversationRuntime(.main))
      let chosen = Runtime(provider: .codex, model: "gpt-5", effort: .high)

      _ = try await host.run(SetConversationRuntime(chosen, for: .main))

      #expect(
        await value(feed) { $0.runtime == chosen } == RuntimeInUse(runtime: chosen, kindDefault: chosen, isOwn: false))
      #expect(try await host.run(ReadConversationRuntime(item)) == Runtime(provider: .codex))
    }
  }

  @Test func aConversationsOwnChoiceLeavesTheOthersOfItsKindOnTheDefault() async throws {
    try await withHost(agent: Self.agent) { host, _, _ in
      let raft = try await article(host, "raft")
      let paxos = try await article(host, "paxos")

      _ = try await host.run(SetConversationRuntime(Self.reading, for: raft))

      #expect(
        try await use(raft, on: host)
          == RuntimeInUse(runtime: Self.reading, kindDefault: Runtime(provider: .codex), isOwn: true))
      #expect(try await host.run(ReadConversationRuntime(paxos)) == Runtime(provider: .codex))
    }
  }

  @Test func aKindsDefaultMovesEveryConversationOfItThatDidNotChooseItsOwn() async throws {
    try await withHost(agent: Self.agent) { host, _, _ in
      let raft = try await article(host, "raft")
      let paxos = try await article(host, "paxos")
      let own = Runtime(provider: .codex, model: "own")
      _ = try await host.run(SetConversationRuntime(own, for: raft))

      _ = try await host.run(SetDefaultRuntime(Self.reading, for: .item))

      #expect(try await host.run(ReadConversationRuntime(paxos)) == Self.reading)
      #expect(try await host.run(ReadConversationRuntime(raft)) == own)
      #expect(try await host.run(ReadConversationRuntime(.course(EntityID()))) == Runtime(provider: .codex))
    }
  }

  @Test func aConversationFollowsItsKindAgainWhenItChoosesTheDefaultOrNothing() async throws {
    try await withHost(agent: Self.agent) { host, _, _ in
      let raft = try await article(host, "raft")
      let paxos = try await article(host, "paxos")
      _ = try await host.run(SetConversationRuntime(Self.reading, for: raft))
      _ = try await host.run(SetConversationRuntime(Self.reading, for: paxos))

      _ = try await host.run(SetConversationRuntime(Runtime(provider: .codex), for: raft))
      _ = try await host.run(SetConversationRuntime(nil, for: paxos))
      _ = try await host.run(SetDefaultRuntime(Runtime(provider: .codex, effort: .low), for: .item))

      #expect(try await use(raft, on: host).isOwn == false)
      #expect(try await host.run(ReadConversationRuntime(paxos)) == Runtime(provider: .codex, effort: .low))
    }
  }

  @Test func makingAConversationsChoiceTheDefaultLetsItFollowTheDefault() async throws {
    try await withHost(agent: Self.agent) { host, _, _ in
      let raft = try await article(host, "raft")
      _ = try await host.run(SetConversationRuntime(Self.reading, for: raft))

      _ = try await host.run(SetDefaultRuntime(Self.reading, for: .item))

      #expect(
        try await use(raft, on: host) == RuntimeInUse(runtime: Self.reading, kindDefault: Self.reading, isOwn: false))
    }
  }

  @Test func theOverviewHasEveryKindAndTheConversationsThatChoseTheirOwn() async throws {
    try await withHost(agent: Self.agent) { host, _, _ in
      let raft = try await article(host, "raft")
      _ = try await host.run(SetConversationRuntime(Self.reading, for: raft))
      _ = try await host.run(SetConversationRuntime(Self.reading, for: .course(EntityID())))

      let overview = try await RuntimeOverview().value(from: host)

      #expect(overview.kinds.map(\.kind) == ConversationKind.allCases)
      #expect(overview.kinds.allSatisfy { $0.runtime == Runtime(provider: .codex) })
      #expect(overview.own == [.init(conversation: raft, title: "raft", runtime: Self.reading)])
    }
  }

  @Test func aConversationThatAlreadyTalkedMovesWithItsKindsDefault() async throws {
    try await withHost(agent: Self.agent) { host, _, world in
      let raft = try await article(host, "raft")
      try await say("Why?", in: raft, on: host)

      _ = try await host.run(SetDefaultRuntime(Self.reading, for: .item))
      try await say("And?", in: raft, on: host, prompts: 2)

      #expect(world.agent.opened.map(\.model) == [nil, "reading"])
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

  /// Up to 1.8.7 every conversation kept the runtime it first opened on: the ones on their kind's latest choice
  /// follow it from now, the others keep theirs, and the main conversation's is its kind's default.
  @Test func anUpgradeLetsConversationsOnTheirKindsLatestChoiceFollowIt() async throws {
    let place = Place()
    defer { place.remove() }
    try FileManager.default.createDirectory(at: place.root, withIntermediateDirectories: true)
    try Data(#"{"latestRuntimes":{"item":{"provider":"codex","model":"reading"}}}"#.utf8).write(
      to: place.root.appending(path: "settings.json"))
    let (same, other) = (ConversationRef.item(EntityID()), ConversationRef.item(EntityID()))
    let database = try StoreDatabase.open(at: place.database)
    let at = Timestamp(millisecondsSince1970: 0)
    try database.setRuntime(Self.reading, of: same, at: at)
    try database.setRuntime(Runtime(provider: .codex, model: "older"), of: other, at: at)
    try database.setRuntime(Runtime(provider: .codex, model: "main"), of: .main, at: at)
    let world = TestWorld(agent: Self.agent)
    let host = try await LocalHost.start(root: place.root, database: place.database, environment: world.environment)

    _ = try await host.run(SetDefaultRuntime(Runtime(provider: .codex, model: "newer"), for: .item))

    #expect(try await host.run(ReadConversationRuntime(same)) == Runtime(provider: .codex, model: "newer"))
    #expect(try await host.run(ReadConversationRuntime(other)) == Runtime(provider: .codex, model: "older"))
    #expect(
      try await use(.main, on: host)
        == RuntimeInUse(
          runtime: Runtime(provider: .codex, model: "main"), kindDefault: Runtime(provider: .codex, model: "main"),
          isOwn: false))
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
