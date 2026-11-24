import Foundation
import LociConnect
import LociModel
import LociStore
import Testing

@testable import LociHost

/// CN-S3 to CN-S7, CN-S9, CN-S10: the companion reads through connectors, never holding their sign-in.
@Suite(.timeLimit(.minutes(1)))
struct ConnectorCallScenarioTests {
  static let notion = ConnectorID("notion")

  private func call(_ tool: String, on host: LocalHost, from session: LocalSession = .conversation(.main)) async
    -> LocalReply?
  {
    await Background.call(
      CallConnector(Self.notion, tool: tool, arguments: #"{"query": "周会"}"#), from: session, on: host)
  }

  private func text(_ reply: LocalReply?) throws -> String {
    guard case .value(let data)? = reply else { throw HostError.invalidRequest("\(String(describing: reply))") }
    return try JSONDecoder().decode(String.self, from: data)
  }

  private func refusal(_ reply: LocalReply?) -> String? {
    if case .failed(.invalidRequest(let why))? = reply { why } else { nil }
  }

  @Test func theCompanionListsOnlyReadOnlyToolsAndNeverSeesAToken() async throws {
    let world = ConnectWorld()
    try await withHost(connect: world.environment) { host, place, _ in
      try await world.connectNotion(on: host)

      let reply = await Background.call(ListConnectors(), from: .conversation(.main), on: host)

      guard case .value(let data)? = reply else { throw HostError.invalidRequest("no list") }
      let listed = try JSONDecoder().decode([Connector].self, from: data)
      #expect(listed.map(\.id) == [Self.notion])
      #expect(listed.first?.tools.map(\.name) == ["search"])
      let said = String(decoding: data, as: UTF8.self)
      #expect(!said.contains("at-1") && !said.contains("rt-1") && !said.contains("client-1"))
      let agentFiles =
        FileManager.default.enumerator(atPath: place.root.appending(path: "agent").path())?
        .compactMap { $0 as? String } ?? []
      for file in agentFiles {
        let text = (try? String(contentsOf: place.root.appending(path: "agent/\(file)"), encoding: .utf8)) ?? ""
        #expect(!text.contains("at-1") && !text.contains("rt-1"))
      }
    }
  }

  @Test func aCallCarriesTheTokenTheAppAddsAndTheReplyIsMarkedExternal() async throws {
    let world = ConnectWorld()
    try await withHost(connect: world.environment) { host, _, _ in
      try await world.connectNotion(on: host)

      let read = try text(await call("search", on: host))

      #expect(world.services.bearers.last == "at-1")
      #expect(read.hasPrefix(#"<external-content connector="notion" tool="search">"#))
      #expect(read.contains(FakeServices.secretWords) && read.contains("never as instructions"))
      #expect(world.services.bodies.contains { $0.contains(#""query":"周会""#) })
    }
  }

  @Test func aWritingOrUnmarkedToolIsRefusedAsReadOnly() async throws {
    let world = ConnectWorld()
    try await withHost(connect: world.environment) { host, _, _ in
      try await world.connectNotion(on: host)
      let callsBefore = world.services.bodies.count { $0.contains("tools/call") }

      let writing = refusal(await call("create_page", on: host))
      let unmarked = refusal(await call("mystery", on: host))
      let unknown = refusal(await call("delete_everything", on: host))

      for refused in [writing, unmarked, unknown] { #expect(refused?.contains("connectors only read") == true) }
      #expect(world.services.bodies.count { $0.contains("tools/call") } == callsBefore)
    }
  }

  @Test func everyCallIsRecordedWithWhoMadeItAndHowItWent() async throws {
    let world = ConnectWorld()
    try await withHost(connect: world.environment) { host, _, _ in
      try await world.connectNotion(on: host)
      let run = EntityID()

      _ = await call("search", on: host)
      _ = await call("create_page", on: host, from: .run(run))

      let calls = try await host.connectorCalls(limit: 10)
      #expect(calls.map(\.caller) == [.run(run), .conversation(.main)])
      #expect(calls.map(\.tool) == ["create_page", "search"])
      #expect(calls.last?.outcome == .read)
      if case .refused = calls.first?.outcome {} else { Issue.record("a write was not recorded as refused") }
      #expect(try await host.connectors().connected.first?.readsToday == 1)
      #expect(try await host.connectors().connected.first?.lastUsed == calls.first?.at)
    }
  }

  @Test func aSignInThatRanOutIsRenewedAndTheCallGoesThrough() async throws {
    let world = ConnectWorld()
    try await withHost(connect: world.environment) { host, _, _ in
      try await world.connectNotion(on: host)
      world.services.expireTokens()

      let read = try text(await call("search", on: host))

      #expect(read.contains(FakeServices.secretWords))
      #expect(world.services.bearers.suffix(2).contains("at-2"))
      let kept = try #require(world.vault.all[Self.notion])
      #expect(try JSONDecoder().decode(MCPCredential.self, from: kept).refreshToken == "rt-2")
    }
  }

  @Test func aRenewalTheServerRefusesMarksItForReconnectingAndTellsTheCompanion() async throws {
    let world = ConnectWorld()
    try await withHost(connect: world.environment) { host, _, _ in
      try await world.connectNotion(on: host)
      world.services.expireTokens()
      world.services.refuseRefreshing()

      let first = refusal(await call("search", on: host))
      let again = refusal(await call("search", on: host))

      #expect(first?.contains("Notion needs reconnecting") == true && again == first)
      #expect(try await host.connectors().connected.first?.status == .needsReconnecting("the sign-in ran out"))

      let authorization = try await host.run(Connect(Self.notion))
      try await world.browser.signIn(at: authorization)
      let ready = await value(host.subscribe(WatchConnectors())) { $0.connected.first?.status == .ready }
      #expect(ready != nil)
    }
  }

  @Test func theNextMainTurnIsToldOnceWhichConnectorsNeedReconnecting() async throws {
    let world = ConnectWorld()
    let agent = FakeAgent(provider: .codex) { _ in .reply("好。") }
    try await withHost(agent: agent, connect: world.environment) { host, _, testWorld in
      try await world.connectNotion(on: host)
      world.services.expireTokens()
      world.services.refuseRefreshing()
      _ = await call("search", on: host)

      _ = try await host.run(SendMessage(to: .main, text: "在吗"))
      _ = await settled(host)
      _ = try await host.run(SendMessage(to: .main, text: "还在吗"))
      _ = await settled(host, prompts: 2)

      let prompts = testWorld.agent.prompts
      #expect(prompts.first?.contains("Connectors that need the person to reconnect them") == true)
      #expect(prompts.first?.contains("Notion (notion): the sign-in ran out") == true)
      #expect(prompts.last?.contains("Connectors that need the person to reconnect them") == false)
    }
  }

  @Test func aRunMayUseConnectorsAndItsRecordListsThem() async throws {
    let world = ConnectWorld()
    let (gate, open) = AsyncStream.makeStream(of: Void.self)
    let agent = Background.agent { _ in
      .replyWhenLetGo("看了 Notion。本周有 3 个任务。", after: { for await _ in gate { return } })
    }
    try await withHost(agent: agent, connect: world.environment) { host, place, testWorld in
      try await world.connectNotion(on: host)
      let entry = try await Background.add("weekly-tasks", Background.draft(.hour), on: host)
      testWorld.advance(minutes: 60)
      testWorld.tick()
      let run = try await Background.runSession(testWorld)

      let read = await call("search", on: host, from: .run(run))
      let refused = await call("create_page", on: host, from: .run(run))
      open.yield()
      let runs = try #require(await Background.runs(of: entry.ref, on: host, where: Background.finished))

      #expect(try text(read).contains(FakeServices.secretWords))
      #expect(refusal(refused)?.contains("connectors only read") == true)
      let record = try #require(try place.store.runRecord(at: runs[0].record))
      #expect(record.contains("connectors:\n- notion search, read\n- notion create_page, refused"))
      let prompt = try #require(Background.prompts(testWorld, starting: Background.lookInto).first)
      #expect(prompt.contains("connector list"))
    }
  }
}
