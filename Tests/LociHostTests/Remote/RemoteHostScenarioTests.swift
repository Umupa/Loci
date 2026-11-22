import Foundation
import LociModel
import LociRemote
import Testing

@testable import LociHost

/// R-S5, R-S6, R-S7, R-S9, R-S11: working on another Mac through the relay.
@Suite(.timeLimit(.minutes(1)))
struct RemoteHostScenarioTests {
  static func settled(_ host: any LociModel.Host, prompts: Int) async -> Conversation? {
    await value(host.subscribe(OneConversation(.main))) { conversation in
      conversation.turn == nil
        && conversation.messages.count { if case .prompt = $0.body { true } else { false } } == prompts
    }
  }

  /// R-S5: Loci on the studio answers the laptop, and the reply streams in while it is written.
  @Test func theOtherMacsLociAnswersAndTheReplyStreamsIn() async throws {
    try await TwoMacs.with(agent: FakeAgent { _ in .hang }) { macs in
      try await macs.pair()
      let studio = macs.laptop.service.open(macs.studio.machine.id)

      _ = try await studio.run(SendMessage(to: .main, text: "Hi"))

      let partial = await value(studio.subscribe(OneConversation(.main))) { conversation in
        conversation.turn?.messages.contains { if case .reply(let text) = $0.body { text == "Working" } else { false } }
          == true
      }
      #expect(partial != nil)
      _ = try await studio.run(StopTurn(in: .main))
      #expect(await Self.settled(studio, prompts: 1) != nil)
    }
  }

  /// R-S9: the studio's own window and the laptop follow the same conversation.
  @Test func bothMacsSeeTheSameConversation() async throws {
    try await TwoMacs.with { macs in
      try await macs.pair()
      let remote = macs.laptop.service.open(macs.studio.machine.id)

      _ = try await remote.run(SendMessage(to: .main, text: "Hi"))

      let here = try #require(await Self.settled(macs.studio.local, prompts: 1))
      let there = try #require(await Self.settled(remote, prompts: 1))
      #expect(here.messages == there.messages)
      #expect(try await macs.laptop.local.conversation(.main).entries.isEmpty)
    }
  }

  /// Loci lives on its Mac: the laptop sees and changes the studio's Loci, and its own stays as it was.
  @Test func theOtherMacsLociIsTheOneOnThatMac() async throws {
    try await TwoMacs.with { macs in
      try await macs.pair()
      let remote = macs.laptop.service.open(macs.studio.machine.id)

      _ = try await remote.run(SaveSoul(core: "You are the studio's Loci."))

      let there = await value(remote.subscribe(LociHome())) { $0.soul.core == "You are the studio's Loci." }
      #expect(there != nil)
      let soul = "agent/SOUL.md"
      let studio = try String(contentsOf: macs.studio.place.root.appending(path: soul), encoding: .utf8)
      let laptop = try String(contentsOf: macs.laptop.place.root.appending(path: soul), encoding: .utf8)
      #expect(studio.contains("You are the studio's Loci."))
      #expect(!laptop.contains("the studio's"))
      #expect(await remote.localFile(.agentFolder) == nil)
    }
  }

  @Test func renamingAPairedLibrarysCompanionChangesOnlyThatLibrary() async throws {
    try await TwoMacs.with { macs in
      try await macs.pair()
      let remote = macs.laptop.service.open(macs.studio.machine.id)
      let names = remote.subscribe(CompanionName())
      #expect(await value(names) { $0.isEmpty } == "")

      _ = try await remote.run(RenameCompanion("小满"))

      #expect(await value(names) { $0 == "小满" } == "小满")
      #expect(try await macs.studio.local.companionName() == "小满")
      #expect(try await macs.laptop.local.companionName().isEmpty)
    }
  }

  @Test func aSubscriptionFollowsTheMacAcrossARelayRestart() async throws {
    try await TwoMacs.with { macs in
      try await macs.pair()
      let remote = macs.laptop.service.open(macs.studio.machine.id)
      let items = remote.subscribe(AllItems())
      #expect(await value(items) { $0.isEmpty } != nil)

      await macs.relay.restart()
      #expect(await macs.connected(macs.laptop, to: macs.studio))
      _ = try await macs.studio.local.run(AddTextItem(fileName: "cfs.md", text: "# CFS"))

      #expect(await value(items) { $0.count == 1 } != nil)
    }
  }

  /// R-S7: while the studio is away, what the laptop saw is still there, and writing fails plainly.
  @Test func whileAMacIsOfflineWhatWasSeenCanStillBeRead() async throws {
    try await TwoMacs.with { macs in
      try await macs.pair()
      let remote = macs.laptop.service.open(macs.studio.machine.id)
      let item = try await remote.run(AddTextItem(fileName: "cfs.md", text: "# CFS"))
      #expect(await value(remote.subscribe(AllItems())) { $0.count == 1 } != nil)
      let page = try await remote.run(ListItems())
      _ = try await remote.run(SendMessage(to: .main, text: "Hi"))
      let said = try #require(await Self.settled(remote, prompts: 1))

      await macs.studio.service.stop()
      #expect(await macs.connected(macs.laptop, to: macs.studio, link: .offline))

      #expect(try await remote.run(ListItems()) == page)
      #expect(await value(remote.subscribe(AllItems())) { $0.map(\.id) == [item.id] } != nil)
      #expect(await value(remote.subscribe(OneConversation(.main))) { $0.messages == said.messages } != nil)
      await #expect(throws: HostError.offline) { _ = try await remote.run(SendMessage(to: .main, text: "Hi")) }
    }
  }

  @Test func whatWasNeverSeenIsUnavailableWhileOffline() async throws {
    try await TwoMacs.with { macs in
      try await macs.pair()
      let remote = macs.laptop.service.open(macs.studio.machine.id)
      await macs.studio.service.stop()
      #expect(await macs.connected(macs.laptop, to: macs.studio, link: .offline))

      await #expect(throws: HostError.offline) { _ = try await remote.run(ListItems()) }
      #expect(await first(remote.subscribe(AllItems())) { $0 == .unavailable(.offline) } != nil)
    }
  }

  /// R-S11: the relay carries only ciphertext.
  @Test func theRelaySeesNoTextFromTheMacs() async throws {
    try await TwoMacs.with { macs in
      try await macs.pair()
      let remote = macs.laptop.service.open(macs.studio.machine.id)

      _ = try await remote.run(SendMessage(to: .main, text: "Teach me the Linux scheduler"))
      _ = try #require(await Self.settled(remote, prompts: 1))

      let seen = await macs.relay.traffic.reduce(Data(), +)
      #expect(seen.range(of: Data("Linux scheduler".utf8)) == nil)
      #expect(seen.range(of: Data("Hello there.".utf8)) == nil)
      #expect(seen.range(of: Data("Mac Studio".utf8)) == nil)
    }
  }

  @Test func aFileOnThisMacIsSentToTheOtherBeforeItIsImported() async throws {
    try await TwoMacs.with { macs in
      try await macs.pair()
      let remote = macs.laptop.service.open(macs.studio.machine.id)
      let file = macs.laptop.place.root.appending(path: ".outside/notes.txt")
      try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data(repeating: 7, count: 700_000).write(to: file)

      let upload = try await remote.upload(LocalFile(file))

      await #expect(throws: HostError.invalidRequest("notes.txt is not a video or audio file")) {
        _ = try await remote.run(ImportMediaFile(upload: upload, mode: .copy))
      }
      await #expect(throws: HostError.self) { _ = try await remote.run(ImportMediaFile(upload: upload, mode: .link)) }
      #expect(await remote.localFile(.dataFolder) == nil)
    }
  }

  /// R-S6: bytes go on their own connection (after the invite and the control connection), so a large
  /// reply does not hold up the conversation.
  @Test func bytesAndCommandsTravelOnSeparateConnections() async throws {
    try await TwoMacs.with { macs in
      try await macs.pair()
      let remote = macs.laptop.service.open(macs.studio.machine.id)
      let item = try await remote.run(AddTextItem(fileName: "cfs.md", text: "# CFS"))

      async let image = try? remote.run(ReadItemImage(item: item.id, name: "missing.png"))
      for _ in 0..<5 { _ = try await remote.run(ListItems()) }
      _ = await image

      #expect(await macs.relay.clientDials(to: macs.studio.key.routeToken) == 3)
    }
  }
}
