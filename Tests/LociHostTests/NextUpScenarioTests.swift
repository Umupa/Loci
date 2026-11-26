import Foundation
import LociModel
import LociStore
import Testing

@testable import LociHost

/// NX-S1–NX-S5, NX-S8: cards on the deck from the companion and from reminder conditions, and what the
/// person does with them.
@Suite(.timeLimit(.minutes(1)))
struct NextUpScenarioTests {
  static let field = SourceField("prem.513100.premium")!

  static func deck(_ host: LocalHost, _ home: Home = .chat) async throws -> [NextUp] {
    try await host.nextUps(of: home)
  }

  static func add(
    _ what: String, asking question: String = "要不要现在申购？", in session: LocalSession = .conversation(.main),
    on host: LocalHost
  ) async throws -> NextUp {
    let reply = await Background.call(AddNextUp(what, asking: question), from: session, on: host)
    guard case .value(let data)? = reply else { throw HostError.invalidRequest("\(String(describing: reply))") }
    return try JSONDecoder().decode(NextUp.self, from: data)
  }

  static func snapshot(_ premium: Double, at moment: Timestamp) -> SourceSnapshot {
    SourceSnapshot(fetched: moment, records: ["513100": ["premium": .number(premium)]])
  }

  @Test func aConditionBringsUpACardOnlyAsItTurnsTrue() async throws {
    let runner = FakeSources(records: ["513100": ["premium": .number(0.034)]])
    try await withHost(sources: runner) { host, _, world in
      _ = try await host.run(SaveDataSource(DataSourceScenarioTests.source))
      let condition = AddNextUpCondition(
        Self.field, .below, 0.03, say: "513100 溢价回到 {value}", asking: "要不要现在申购？")
      #expect(RunToolScenarioTests.worked(await Background.call(condition, from: .conversation(.main), on: host)))
      let key = SourceKey(.chat, "prem")
      let conditions = host.nextUpConditions

      for premium in [0.028, 0.027, 0.026] {
        world.advance(minutes: 1)
        await conditions.refreshed(key, Self.snapshot(premium, at: world.now))
      }

      let deck = try await Self.deck(host)
      #expect(deck.map(\.what) == ["513100 溢价回到 0.028"])
      #expect(deck.first?.kind == .ask(question: "要不要现在申购？"))
      #expect(try await host.run(ListNextUpConditions()).first?.holds == true)
    }
  }

  @Test func theFetchingLineBringsUpACardWhenAFetchCrossesTheThreshold() async throws {
    let runner = FakeSources(records: ["513100": ["premium": .number(0.034)]])
    try await withHost(sources: runner) { host, _, world in
      _ = try await host.run(SaveDataSource(DataSourceScenarioTests.source))
      _ = try await host.run(AddNextUpCondition(Self.field, .below, 0.03, say: "溢价回到 {value}", asking: "买吗"))

      world.advance(minutes: 1)
      #expect(await SourceLineTests.look(host) == 1)
      #expect(try await Self.deck(host).isEmpty)

      runner.set(["513100": ["premium": .number(0.028)]])
      world.advance(minutes: 1)
      #expect(await SourceLineTests.look(host) == 1)
      world.advance(minutes: 1)
      #expect(await SourceLineTests.look(host) == 1)

      #expect(try await Self.deck(host).map(\.what) == ["溢价回到 0.028"])
    }
  }

  @Test func savingASourceAgainChecksItsConditions() async throws {
    let runner = FakeSources(records: ["513100": ["premium": .number(0.034)]])
    try await withHost(sources: runner) { host, _, world in
      _ = try await host.run(SaveDataSource(DataSourceScenarioTests.source))
      _ = try await host.run(AddNextUpCondition(Self.field, .below, 0.03, say: "低了", asking: "买吗"))
      runner.set(["513100": ["premium": .number(0.028)]])
      world.advance(minutes: 1)

      _ = try await host.run(SaveDataSource(DataSourceScenarioTests.source))

      #expect(try await Self.deck(host).map(\.what) == ["低了"])
      #expect(try await host.run(ListNextUpConditions()).first?.firedAt == world.now)
    }
  }

  @Test func aConditionNeedsASourceOfItsHome() async throws {
    try await withHost { host, _, _ in
      let condition = AddNextUpCondition(Self.field, .below, 0.03, say: "x", asking: "y")
      let reply = await Background.call(condition, from: .conversation(.main), on: host)

      guard case .failed(.notFound)? = reply else { throw HostError.invalidRequest("\(String(describing: reply))") }
    }
  }

  @Test func aDeclinedConditionBringsUpNoMoreCards() async throws {
    let runner = FakeSources(records: ["513100": ["premium": .number(0.034)]])
    try await withHost(sources: runner) { host, _, world in
      _ = try await host.run(SaveDataSource(DataSourceScenarioTests.source))
      _ = try await host.run(AddNextUpCondition(Self.field, .below, 0.03, say: "低了", asking: "买吗"))
      let key = SourceKey(.chat, "prem")
      await host.nextUpConditions.refreshed(key, Self.snapshot(0.028, at: world.now))
      let card = try #require(try await Self.deck(host).first)

      _ = try await host.run(SetNextUp(card.id, .decline, version: card.version))
      world.advance(minutes: 600)
      await host.nextUpConditions.refreshed(key, Self.snapshot(0.035, at: world.now))
      world.advance(minutes: 1)
      await host.nextUpConditions.refreshed(key, Self.snapshot(0.028, at: world.now))

      #expect(try await Self.deck(host).isEmpty)
    }
  }

  @Test func startingACardSaysItsQuestionInItsProjectAsThePerson() async throws {
    try await withHost(agent: FakeAgent(provider: .codex)) { host, _, world in
      let project = try await ProjectScenarioTests.start(host)
      let card = try await Self.add(
        "费城半导体跌 8%", asking: "这对我意味着什么", in: .conversation(.project(project)), on: host)
      #expect(card.home == .project(project))

      _ = try await host.run(StartNextUp(card.id, version: card.version))

      _ = try #require(await settled(host, .project(project), prompts: 2))
      #expect(world.agent.prompts.last?.typed.hasSuffix("\n这对我意味着什么") == true)
      #expect(try await Self.deck(host).isEmpty)
    }
  }

  @Test func aCardStartedWhileTheConversationIsAnsweringIsSaidOnceTheAnswerEnds() async throws {
    let agent = FakeAgent(provider: .codex) { prompt in prompt.hasSuffix("在吗") ? .hang : .reply("好") }
    try await withHost(agent: agent) { host, _, world in
      let card = try await Self.add("纳指回撤", asking: "还定投吗", on: host)
      _ = try await host.run(SendMessage(to: .main, text: "在吗"))

      let started = Task { try await host.run(StartNextUp(card.id, version: card.version)) }
      try await Background.quiet()
      #expect(try await Self.deck(host).isEmpty)
      #expect(!world.agent.prompts.contains { $0.hasSuffix("还定投吗") })
      _ = try await host.run(StopTurn(in: .main))
      _ = try await started.value

      _ = try #require(await settled(host, prompts: 2))
      #expect(world.agent.prompts.filter { $0.hasSuffix("还定投吗") }.count == 1)
      #expect(try host.database.nextUp(card.id)?.place == .started)
    }
  }

  @Test func aCardStartedWhileTheConversationIsAnsweringIsNotSaidIfItsProjectIsArchivedMeanwhile() async throws {
    let agent = FakeAgent(provider: .codex) { prompt in prompt.hasSuffix("在吗") ? .hang : .reply("好") }
    try await withHost(agent: agent) { host, _, world in
      let project = try await ProjectScenarioTests.start(host)
      let card = try await Self.add("纳指回撤", asking: "还定投吗", in: .conversation(.project(project)), on: host)
      _ = try await host.run(SendMessage(to: .project(project), text: "在吗"))

      let started = Task { try await host.run(StartNextUp(card.id, version: card.version)) }
      try await Background.quiet()
      _ = try await host.run(ArchiveProject(project, archived: true))
      _ = try? await host.run(StopTurn(in: .project(project)))
      _ = try? await started.value

      #expect(!world.agent.prompts.contains { $0.hasSuffix("还定投吗") })
      #expect(try host.database.nextUp(card.id)?.place == .new)
    }
  }

  @Test func aKeepFromAMacThatSawTheCardBeforeItWasStartedLeavesItStarted() async throws {
    try await withHost(agent: FakeAgent(provider: .codex)) { host, _, world in
      let card = try await Self.add("纳指回撤", asking: "还定投吗", on: host)
      _ = try await host.run(StartNextUp(card.id, version: card.version))
      _ = try #require(await settled(host))

      await #expect(throws: HostError.invalidRequest(NextUp.changed)) {
        try await host.run(SetNextUp(card.id, .keep, version: card.version))
      }

      #expect(try host.database.nextUp(card.id)?.place == .started)
      #expect(try await Self.deck(host).isEmpty)
      #expect(world.agent.prompts.filter { $0.typed.hasSuffix("还定投吗") }.count == 1)
    }
  }

  @Test func aCardStartedFromTwoMacsAtOnceIsSaidOnce() async throws {
    try await withHost(agent: FakeAgent(provider: .codex)) { host, _, world in
      let card = try await Self.add("纳指回撤", asking: "还定投吗", on: host)

      let results = await withTaskGroup(of: Bool.self) { group in
        for _ in 0..<2 {
          group.addTask { (try? await host.run(StartNextUp(card.id, version: card.version))) != nil }
        }
        return await group.reduce(into: [Bool]()) { $0.append($1) }
      }

      #expect(results.filter { $0 }.count == 1)
      _ = try #require(await settled(host))
      #expect(world.agent.prompts.filter { $0.typed.hasSuffix("还定投吗") }.count == 1)
      #expect(try await Self.deck(host).isEmpty)
    }
  }

  @Test func aCardThatChangedSinceItWasShownIsNotStarted() async throws {
    try await withHost(agent: FakeAgent(provider: .codex)) { host, _, _ in
      let shown = try await Self.add("纳指回撤", asking: "还定投吗", on: host)
      _ = try await host.run(AddNextUp("纳指回撤", asking: "要不要减仓", key: shown.key))

      await #expect(throws: HostError.invalidRequest(NextUp.changed)) {
        try await host.run(StartNextUp(shown.id, version: shown.version))
      }

      #expect(try await Self.deck(host).first?.kind == .ask(question: "要不要减仓"))
    }
  }

  @Test func aCardPutAgainKeepsKeptAndPutOffWhereThePersonPutThem() async throws {
    try await withHost { host, _, _ in
      let kept = try await Self.add("持仓里英伟达占 14%", on: host)
      let later = try await Self.add("JR Pass 12 月起涨价", on: host)
      _ = try await host.run(SetNextUp(kept.id, .keep, version: kept.version))
      _ = try await host.run(SetNextUp(later.id, .later(.after(minutes: 60)), version: later.version))

      _ = try await Self.add("持仓里英伟达占 14%", asking: "再看看", on: host)
      _ = try await Self.add("JR Pass 12 月起涨价", asking: "再看看", on: host)

      #expect(try await Self.deck(host).map(\.id) == [kept.id])
      #expect(try host.database.nextUp(kept.id)?.place == .kept)
    }
  }

  @Test func aKeptCardStaysAPutOffOneComesBackAndADeclinedOneNeverDoes() async throws {
    try await withHost { host, _, world in
      let kept = try await Self.add("持仓里英伟达占 14%", on: host)
      let later = try await Self.add("JR Pass 12 月起涨价", on: host)
      let declined = try await Self.add("新的 ETF 上市", on: host)

      _ = try await host.run(SetNextUp(kept.id, .keep, version: kept.version))
      _ = try await host.run(SetNextUp(later.id, .later(.after(minutes: 60)), version: later.version))
      let away = try await host.run(SetNextUp(declined.id, .decline, version: declined.version))
      #expect(try await Self.deck(host).map(\.what) == ["持仓里英伟达占 14%"])

      world.advance(minutes: 60)
      world.tick()
      _ = await value(host.subscribe(WatchNextUps(of: .chat))) { $0.count == 2 }
      #expect(try await Self.deck(host).map(\.what) == ["JR Pass 12 月起涨价", "持仓里英伟达占 14%"])

      let again = await Background.call(AddNextUp("新的 ETF 上市。", asking: "?"), from: .conversation(.main), on: host)
      #expect(RunToolScenarioTests.refused(again) == NextUp.declinedBefore)

      _ = try await host.run(SetNextUp(declined.id, .restore, version: away.version))
      #expect(try await Self.deck(host).count == 3)
    }
  }

  @Test func pinningACardTwiceLeavesItAsItWas() async throws {
    try await withHost { host, _, _ in
      let card = try await Self.add("持仓里英伟达占 14%", on: host)
      let other = try await Self.add("JR Pass 12 月起涨价", on: host)

      let kept = try await host.run(SetNextUp(card.id, .keep, version: card.version))
      let unpinned = try await host.run(SetNextUp(card.id, .restore, version: kept.version))

      #expect(kept.place == .kept)
      #expect(unpinned.place == .new && unpinned.shownAt == card.shownAt)
      #expect(try await Self.deck(host).map(\.id) == [other.id, card.id])
      await #expect(throws: HostError.invalidRequest(NextUp.changed)) {
        try await host.run(SetNextUp(card.id, .restore, version: kept.version))
      }
    }
  }

  @Test func theSameCardAddedAgainComesToTheTopOnce() async throws {
    try await withHost { host, _, world in
      let first = try await Self.add("纳指回撤", on: host)
      _ = try await Self.add("别的事", on: host)
      world.advance(minutes: 1)
      let again = try await Self.add("纳指回撤", asking: "还定投吗", on: host)

      #expect(again.id == first.id)
      #expect(try await Self.deck(host).map(\.what) == ["纳指回撤", "别的事"])
    }
  }

  @Test func aRunPutsACardOnItsOwnHomesDeck() async throws {
    try await withHost(agent: Background.agent { _ in .hang }) { host, _, world in
      let project = try await ProjectScenarioTests.start(host)
      _ = try await ProjectBackgroundTests.addSchedule(in: project, on: host)
      world.advance(minutes: 60)
      world.tick()
      let session = LocalSession.run(try await Background.runSession(world))

      let card = try await Self.add("纳指回撤到二十日线", in: session, on: host)

      #expect(card.home == .project(project))
      #expect(try await Self.deck(host, .project(project)).map(\.id) == [card.id])
    }
  }

  @Test func theDailyReviewPutsNoCards() async throws {
    let agent = FakeAgent(provider: .codex) { prompt in prompt.hasPrefix("It is the end of") ? .hang : .reply("Hi.") }
    try await withHost(agent: agent) { host, _, world in
      world.set(to: "22:00")
      _ = try await host.run(SendMessage(to: .main, text: "Hi"))
      _ = await settled(host)
      world.set(to: "23:30")
      world.tick()
      let session = LocalSession.run(try await Background.runSession(world))

      let reply = await Background.call(AddNextUp("x", asking: "y"), from: session, on: host)

      #expect(RunToolScenarioTests.refused(reply) == RunPolicy.review.refusal("next add"))
    }
  }

  @Test func theChatsDeckHasEveryOpenHomesCardsAndAProjectsOnlyItsOwn() async throws {
    try await withHost(agent: FakeAgent(provider: .codex)) { host, _, _ in
      let project = try await ProjectScenarioTests.start(host)
      let other = try await ProjectScenarioTests.start(host, named: "旅行")
      _ = try await Self.add("聊天的", on: host)
      _ = try await Self.add("投资的", in: .conversation(.project(project)), on: host)
      _ = try await Self.add("旅行的", in: .conversation(.project(other)), on: host)

      #expect(Set(try await Self.deck(host).map(\.what)) == ["聊天的", "投资的", "旅行的"])
      #expect(try await Self.deck(host, .project(project)).map(\.what) == ["投资的"])

      _ = try await host.run(ArchiveProject(other, archived: true))
      #expect(Set(try await Self.deck(host).map(\.what)) == ["聊天的", "投资的"])

      _ = try await host.run(DeleteProject(project))
      _ = try await host.run(ArchiveProject(other, archived: false))
      _ = try await host.run(DeleteProject(other))
      #expect(try host.database.nextUps(of: [.project(project)]).isEmpty)
    }
  }
}
