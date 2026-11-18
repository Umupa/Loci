import Foundation
import LociModel
import LociRemote
import Testing

@testable import LociHost

/// R-S5, R-S6, R-S7, R-S9, R-S11: working on another Mac through the relay.
@Suite(.timeLimit(.minutes(1)))
struct RemoteHostScenarioTests {
  static let agent = FakeAgent { prompt in prompt.contains("new mentor") ? .reply("Ready.") : .reply("Hello there.") }

  static func settled(_ host: any LociModel.Host, _ mentor: EntityID, turns: Int) async -> Conversation? {
    await value(host.subscribe(MentorConversation(mentor: mentor))) { conversation in
      conversation.turn == nil
        && conversation.messages.count { if case .prompt = $0.body { true } else { false } } == turns
    }
  }

  /// R-S5: a mentor on the studio answers the laptop, and the reply streams in while it is written.
  @Test func aRemoteMentorsReplyStreamsIn() async throws {
    let agent = FakeAgent { prompt in prompt.contains("new mentor") ? .reply("Ready.") : .hang }
    try await TwoMacs.with(agent: agent) { macs in
      try await macs.pair()
      let studio = macs.laptop.service.open(macs.studio.machine.id)
      let mentor = try await studio.run(CreateMentor(request: "Scheduling"))
      _ = try #require(await Self.settled(studio, mentor.id, turns: 1))

      _ = try await studio.run(SendMessage(mentor: mentor.id, text: "Hi"))

      let partial = await value(studio.subscribe(MentorConversation(mentor: mentor.id))) { conversation in
        conversation.turn?.messages.contains { if case .reply(let text) = $0.body { text == "Working" } else { false } }
          == true
      }
      #expect(partial != nil)
      _ = try await studio.run(StopTurn(mentor: mentor.id))
      #expect(await Self.settled(studio, mentor.id, turns: 2) != nil)
    }
  }

  /// R-S9: the studio's own window and the laptop follow the same conversation.
  @Test func bothMacsSeeTheSameConversation() async throws {
    try await TwoMacs.with(agent: Self.agent) { macs in
      try await macs.pair()
      let remote = macs.laptop.service.open(macs.studio.machine.id)
      let mentor = try await macs.studio.local.run(CreateMentor(request: "Scheduling"))
      _ = try #require(await Self.settled(macs.studio.local, mentor.id, turns: 1))

      _ = try await remote.run(SendMessage(mentor: mentor.id, text: "Hi"))

      let here = try #require(await Self.settled(macs.studio.local, mentor.id, turns: 2))
      let there = try #require(await Self.settled(remote, mentor.id, turns: 2))
      #expect(here.messages == there.messages)
    }
  }

  @Test func aSubscriptionFollowsTheMacAcrossARelayRestart() async throws {
    try await TwoMacs.with { macs in
      try await macs.pair()
      let remote = macs.laptop.service.open(macs.studio.machine.id)
      let mentors = remote.subscribe(AllMentors())
      #expect(await value(mentors) { $0.isEmpty } != nil)

      await macs.relay.restart()
      #expect(await macs.connected(macs.laptop, to: macs.studio))
      _ = try await macs.studio.local.run(CreateMentor(request: "Scheduling"))

      #expect(await value(mentors) { $0.count == 1 } != nil)
    }
  }

  /// R-S7: while the studio is away, what the laptop saw is still there, and writing fails plainly.
  @Test func whileAMacIsOfflineWhatWasSeenCanStillBeRead() async throws {
    try await TwoMacs.with { macs in
      try await macs.pair()
      let remote = macs.laptop.service.open(macs.studio.machine.id)
      let mentor = try await remote.run(CreateMentor(request: "Scheduling"))
      #expect(await value(remote.subscribe(AllMentors())) { $0.count == 1 } != nil)
      let page = try await remote.run(ListMentors())

      await macs.studio.service.stop()
      #expect(await macs.connected(macs.laptop, to: macs.studio, link: .offline))

      #expect(try await remote.run(ListMentors()) == page)
      #expect(await value(remote.subscribe(AllMentors())) { $0.map(\.id) == [mentor.id] } != nil)
      await #expect(throws: HostError.offline) { _ = try await remote.run(SendMessage(mentor: mentor.id, text: "Hi")) }
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
    try await TwoMacs.with(agent: Self.agent) { macs in
      try await macs.pair()
      let remote = macs.laptop.service.open(macs.studio.machine.id)
      let mentor = try await remote.run(CreateMentor(request: "Teach me the Linux scheduler"))
      _ = try #require(await Self.settled(remote, mentor.id, turns: 1))

      let seen = await macs.relay.traffic.reduce(Data(), +)
      #expect(seen.range(of: Data("Linux scheduler".utf8)) == nil)
      #expect(seen.range(of: Data("Ready.".utf8)) == nil)
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
      let mentor = try await remote.run(CreateMentor(request: "Scheduling"))

      async let image = try? remote.run(ReadItemImage(item: mentor.id, name: "missing.png"))
      for _ in 0..<5 { _ = try await remote.run(ReadCatalog(mentor: mentor.id)) }
      _ = await image

      #expect(await macs.relay.clientDials(to: macs.studio.key.routeToken) == 3)
    }
  }
}
