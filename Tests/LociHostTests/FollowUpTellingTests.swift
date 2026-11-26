import Foundation
import LociModel
import LociStore
import Synchronization
import Testing

@testable import LociHost

/// PJ-S6: a follow-up that is done says what came of it as the companion, once, in the conversation it was set
/// in and nowhere else, together with closing it.
@Suite(.timeLimit(.minutes(1)))
struct FollowUpTellingTests {
  /// Says back the one thing each follow-up was for.
  static var agent: FakeAgent {
    FakeAgent(provider: .codex) { prompt in
      guard prompt.hasPrefix(Background.followUp) else { return .reply("好") }
      let what = prompt.split(separator: "\n").first { $0.hasPrefix("> ") }.map { $0.dropFirst(2) } ?? ""
      return .reply("看过了：\(what)。")
    }
  }

  static func told(_ conversation: ConversationRef, on host: LocalHost) -> [String] {
    ((try? host.database.messages(of: .conversation(conversation))) ?? []).compactMap { message in
      if case .told(let text) = message.body { text } else { nil }
    }
  }

  @Test func followUpsSetInDifferentConversationsOfTheChatEachSayOnlyTheirOwn() async throws {
    try await withHost(agent: Self.agent) { host, _, world in
      let first = try await host.run(AddTextItem(fileName: "raft.md", text: "# Raft\n")).id
      let second = try await host.run(AddTextItem(fileName: "paxos.md", text: "# Paxos\n")).id
      let set: [(ConversationRef, String)] = [(.main, "看纳指"), (.item(first), "看 Raft"), (.item(second), "看 Paxos")]
      for (conversation, what) in set {
        _ = await Background.call(AddFollowUp(.after(minutes: 2), what), from: .conversation(conversation), on: host)
      }
      world.advance(minutes: 2)
      world.tick()

      for _ in 0..<1000 where set.contains(where: { Self.told($0.0, on: host).isEmpty }) {
        world.tick()
        try await Task.sleep(for: .milliseconds(10))
      }

      for (conversation, what) in set { #expect(Self.told(conversation, on: host) == ["看过了：\(what)。"]) }
    }
  }

  @Test func whatTheMainChatsFollowUpFoundIsSaidThereAsTheCompanion() async throws {
    try await withHost(agent: Self.agent) { host, _, world in
      _ = await Background.call(AddFollowUp(.after(minutes: 2), "看纳指"), from: .conversation(.main), on: host)
      world.advance(minutes: 2)
      world.tick()
      for _ in 0..<500 where Self.told(.main, on: host).isEmpty { try await Task.sleep(for: .milliseconds(10)) }

      let prompt = try #require(Background.prompts(world, starting: Background.followUp).first)
      #expect(prompt.contains("said as yours in the conversation where you set this"))
      #expect(!prompt.contains("will not see this session"))
      #expect(Self.told(.main, on: host) == ["看过了：看纳指。"])
    }
  }

  @Test func aResultThatComesWhileTheConversationAnswersIsShownOnceAfterItsQuestionAsItIsKept() async throws {
    let (gate, open) = AsyncStream.makeStream(of: Void.self)
    let agent = FakeAgent(provider: .codex) { prompt in
      if prompt.hasPrefix(Background.followUp) {
        return .replyWhenLetGo("看过了。", after: { for await _ in gate { return } })
      }
      return prompt.hasSuffix("等一下") ? .hang : .reply("好")
    }
    try await withHost(agent: agent) { host, _, world in
      _ = await Background.call(AddFollowUp(.after(minutes: 2), "看纳指"), from: .conversation(.main), on: host)
      world.advance(minutes: 2)
      world.tick()
      _ = try await Background.runSession(world)
      _ = try await host.run(SendMessage(to: .main, text: "等一下"))

      open.yield()
      for _ in 0..<500
      where (try? host.database.messages(of: .conversation(.main)))?.contains(where: {
        $0.body == .told("看过了。")
      }) != true {
        try await Task.sleep(for: .milliseconds(10))
      }
      #expect(try await host.conversation(.main).messages.filter { $0.body == .told("看过了。") }.isEmpty)
      _ = try await host.run(StopTurn(in: .main))

      let shown = try await host.conversation(.main).messages.map(\.body)
      let kept = try host.database.messages(of: .conversation(.main)).map(\.body)
      #expect(shown == kept)
      #expect(shown.filter { $0 == .told("看过了。") }.count == 1)
      let asked = try #require(shown.firstIndex { if case .prompt = $0 { true } else { false } })
      #expect(shown.firstIndex(of: .told("看过了。")).map { $0 > asked } == true)
    }
  }

  @Test func aLineSaidAgainUnderTheSameIdIsNotSaidTwiceAndWhatGoesWithItIsStillKept() async throws {
    try await withHost(agent: Self.agent) { host, _, world in
      let id = world.nextID()
      let kept = Mutex(0)

      for _ in 0..<2 {
        try await host.loci.say("看过了。", in: .main, as: id) { line in
          kept.withLock { $0 += 1 }
          if let line { try host.database.append([line.message], to: line.session) }
        }
      }

      #expect(Self.told(.main, on: host) == ["看过了。"])
      #expect(kept.withLock { $0 } == 2)
    }
  }

  @Test func aLineWhoseWriteFailsIsNotSaid() async throws {
    try await withHost(agent: Self.agent) { host, _, world in
      await #expect(throws: HostError.self) {
        try await host.loci.say("看过了。", in: .main, as: world.nextID()) { _ in throw HostError.storage("full") }
      }

      let messages = try await host.conversation(.main).messages
      #expect(Self.told(.main, on: host).isEmpty)
      #expect(messages.isEmpty)
    }
  }
}
