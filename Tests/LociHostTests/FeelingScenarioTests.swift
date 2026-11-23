import Foundation
import LociModel
import Testing

@testable import LociHost

/// L-S21–L-S23: each message tells the companion how it feels and how tired it is, and it changes both with
/// `loci mood`, `loci sleep` and `loci wake`.
@Suite(.timeLimit(.minutes(1)))
struct FeelingScenarioTests {
  private actor Replies {
    var all: [LocalReply] = []
    func add(_ reply: LocalReply) { all.append(reply) }
  }

  private func say(_ text: String, to host: LocalHost, in conversation: ConversationRef = .main, prompts: Int)
    async throws
  {
    _ = try await host.run(SendMessage(to: conversation, text: text))
    _ = try #require(await settled(host, conversation, prompts: prompts))
  }

  private func feel(_ request: FeelingRequest, in session: LocalSession?, on host: LocalHost) async -> LocalReply? {
    let replies = Replies()
    await ToolGateway.answer(LocalCall(session: session, request: .feeling(request)), on: host) {
      await replies.add($0)
    }
    return await replies.all.first
  }

  private func score(_ value: Int) throws -> Score { try #require(Score(value)) }

  @Test func everyMessageSaysHowTheCompanionFeels() async throws {
    try await withHost { host, _, world in
      try await say("早", to: host, prompts: 1)

      let prompt = try #require(world.agent.prompts.first)
      #expect(prompt.contains("Feeling: cheerful, valence 6/10, energy 7/10"))
      #expect(prompt.contains("  Here: nothing yet"))
      #expect(prompt.contains("Fatigue: 2/100, awake"))
    }
  }

  @Test func aConversationsMoodStaysInThatConversation() async throws {
    try await withHost { host, _, world in
      let item = try await host.run(AddTextItem(fileName: "raft.md", text: "# Raft\n\nterm and index\n"))
      let reply = await feel(
        .here(word: "annoyed", valence: try score(2), why: "they skipped my advice"), in: .conversation(.main), on: host
      )
      guard case .value(let data) = try #require(reply) else { throw HostError.invalidRequest("no reply") }
      #expect(try JSONDecoder().decode(String.self, from: data).hasPrefix("Feeling: annoyed, valence 3/10"))

      try await say("还在吗", to: host, prompts: 1)
      try await say("这篇讲什么", to: host, in: .item(item.id), prompts: 1)

      #expect(world.agent.prompts[0].contains("  Here: annoyed, valence 2/10 — they skipped my advice"))
      #expect(world.agent.prompts[1].contains("  Here: nothing yet"))
    }
  }

  @Test func theBaseMoodCanBeSetOutsideAConversationButAConversationMoodCannot() async throws {
    try await withHost { host, _, world in
      let refused = await feel(.here(word: "fine", valence: try score(5), why: "x"), in: nil, on: host)
      #expect(refused == .failed(.invalidRequest(FeelingRequest.scopeMessage)))

      _ = await feel(
        .base(word: "content", valence: try score(8), energy: try score(4), why: "a good day"), in: nil, on: host)
      try await say("晚上好", to: host, prompts: 1)

      #expect(world.agent.prompts[0].contains("  Base mood: content, valence 8/10, energy 4/10 — a good day"))
    }
  }

  @Test func sleepingShowsUntilWokenOrTwoHoursIntoTheDay() async throws {
    try await withHost { host, place, world in
      world.set(to: "23:30")
      _ = await feel(.sleep, in: .conversation(.main), on: host)
      try await say("睡了吗", to: host, prompts: 1)
      _ = await feel(.wake, in: .conversation(.main), on: host)
      try await say("醒醒", to: host, prompts: 2)
      _ = await feel(.sleep, in: .conversation(.main), on: host)
      world.set(to: "10:00", daysLater: 1)
      try await say("早", to: host, prompts: 3)

      let prompts = world.agent.prompts
      #expect(prompts[0].contains(", asleep"))
      #expect(prompts[1].contains(", awake"))
      #expect(prompts[2].contains(", awake"))
      #expect(try place.store.feelings().fatigue.rest == .awake)
    }
  }

  @Test func theCompanionsPageShowsItsMoodAndTiredness() async throws {
    try await withHost { host, _, _ in
      let resting = try #require(try await host.lociPage().feeling)
      #expect(resting.word == nil && resting.why == nil)
      #expect(resting.valence.value == 6 && resting.energy.value == 7 && resting.tiredness == .awake)

      let page = host.subscribe(LociHome())
      _ = await feel(.here(word: "得意", valence: try score(9), why: "终于懂了"), in: .conversation(.main), on: host)
      let moved = try #require(
        await value(page) { $0.feeling?.word == "得意" }?.feeling)
      #expect(moved.why == "终于懂了")
      #expect(moved.valence.value == 8)
      _ = await feel(.sleep, in: .conversation(.main), on: host)
      #expect(await value(page) { $0.feeling?.tiredness == .asleep } != nil)
    }
  }
}
