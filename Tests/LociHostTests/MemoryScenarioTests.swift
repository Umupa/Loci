import Foundation
import LociModel
import LociStore
import Testing

@testable import LociHost

/// ME-S1 to ME-S5, ME-S8: the index, the wiki only the review writes, the review's dreaming, and recall.
@Suite(.timeLimit(.minutes(1)))
struct MemoryScenarioTests {
  static let review = "It is the end of"

  /// Writes what the review is given to write, says hello elsewhere, and tries to write the wiki from there.
  static func agent(review files: [String: String] = [:], elsewhere: [String: String] = [:]) -> FakeAgent {
    FakeAgent(provider: .codex) { prompt in
      prompt.hasPrefix(review)
        ? .write(files, reply: "Done.") : .write(elsewhere, reply: "好。")
    }
  }

  private func talkThenReview(_ host: LocalHost, _ world: TestWorld, daysLater: Int = 0) async throws {
    world.set(to: "22:00", daysLater: daysLater)
    _ = try await host.run(SendMessage(to: .main, text: "今天读了 Raft"))
    _ = await settled(host)
    world.set(to: "23:30")
    world.tick()
    let day = Day(containing: world.now, in: TestWorld.timeZone)
    for _ in 0..<500 {
      if let outcome = try host.database.review(of: day), outcome != .started { return }
      try await Task.sleep(for: .milliseconds(10))
    }
    throw HostError.notFound("review of \(day)")
  }

  private func reviewPrompt(_ world: TestWorld) throws -> String {
    try #require(world.agent.prompts.last { $0.hasPrefix(Self.review) })
  }

  private func writeMemory(_ place: Place, index: String, pages: [String: String] = [:]) throws {
    let store = place.store
    try store.home(.chat).setMemoryWritable(true)
    try store.saveAgentText(index, as: .memory)
    for (name, text) in pages { try store.home(.chat).saveWikiPage(text, as: name) }
    try store.home(.chat).setMemoryWritable(false)
  }

  @Test func onlyTheFirst200LinesOfTheIndexAreShownAndALongerOneIsSaidToBe() async throws {
    try await withHost(agent: Self.agent()) { host, place, world in
      let lines = (1...250).map { "- 2025-11-0\($0 % 9 + 1) fact \($0)" }
      try writeMemory(place, index: "# Memory\n" + lines.joined(separator: "\n"))

      _ = try await host.run(SendMessage(to: .main, text: "在吗"))
      _ = await settled(host)

      let prompt = try #require(world.agent.prompts.last)
      #expect(prompt.contains("fact 199\n") && !prompt.contains("fact 200\n"))
      #expect(prompt.contains("MEMORY.md has 251 lines; only the first 200 are here"))
    }
  }

  @Test func theReviewMayWriteTheWikiAndNoOtherSessionCan() async throws {
    let agent = Self.agent(
      review: ["memory/raft.md": "# Raft\n\n- 2025-11-17 读了 Raft\n"], elsewhere: ["memory/notes.md": "# Sneaked\n"])
    try await withHost(agent: agent) { host, place, world in
      try await talkThenReview(host, world)

      let store = place.store
      #expect(store.home(.chat).wikiPages() == ["raft"])
      #expect(!store.home(.chat).memoryIsWritable)
      #expect(store.home(.chat).memoryChangedSinceKept().isEmpty)
    }
  }

  @Test func theReviewIsToldOfDeadLinksAndOfWhatChangedOutsideIt() async throws {
    try await withHost(agent: Self.agent()) { host, place, world in
      try writeMemory(
        place,
        index: "# Memory\n- 2025-11-10 在学沙箱 [沙箱](memory/sandboxes.md)\n- 2025-11-12 Raft [Raft](memory/raft.md)\n",
        pages: ["raft": "# Raft\n- 2025-11-12 混过 term 和 index\n"])
      try place.store.home(.chat).keepMemory()
      try place.store.home(.chat).setMemoryWritable(true)
      try Data("# Raft\n- changed by hand\n".utf8).write(to: place.root.appending(path: "agent/memory/raft.md"))
      try place.store.home(.chat).setMemoryWritable(false)

      try await talkThenReview(host, world)

      let prompt = try reviewPrompt(world)
      #expect(prompt.contains("MEMORY.md → memory/sandboxes.md"))
      #expect(prompt.contains("These changed outside a review: memory/raft.md"))
      #expect(prompt.contains("conversations/2025-11-17/"))
      #expect(!prompt.contains("go over the whole wiki"))
    }
  }

  @Test func onSundayTheReviewGoesOverTheWholeWiki() async throws {
    try await withHost(agent: Self.agent()) { host, _, world in
      try await talkThenReview(host, world, daysLater: 6)

      #expect(try reviewPrompt(world).contains("It is Sunday: go over the whole wiki"))
    }
  }

  @Test func theFirstReviewAfterUpgradingSplitsTheIndexAndLosesNoEntry() async throws {
    let agent = Self.agent(review: [
      "MEMORY.md": "# Memory\n- 2025-11-02 先给结论，再给依据\n- 2025-11-12 Raft 混过 [Raft](memory/raft.md)\n",
      "memory/raft.md": "# Raft\n- 2025-11-12 term 和 index 混过两次\n",
    ])
    try await withHost(agent: agent) { host, place, world in
      try writeMemory(
        place,
        index: "# Memory\n- 2025-11-02 先给结论，再给依据\n- 2025-11-12 term 和 index 混过两次\n- 2025-11-15 不要出题考\n")

      try await talkThenReview(host, world)

      #expect(try reviewPrompt(world).contains("First, split MEMORY.md"))
      let unsorted = try #require(try place.store.home(.chat).wikiPage("unsorted"))
      #expect(unsorted.contains("- 2025-11-15 不要出题考"))
      #expect(!unsorted.contains("先给结论") && !unsorted.contains("term 和 index"))
      #expect(place.store.home(.chat).memoryChangedSinceKept().isEmpty)
    }
  }

  @Test func theCompanionFindsWhatThePersonSaidWithRecall() async throws {
    try await withHost(agent: Self.agent()) { host, _, _ in
      _ = try await host.run(SendMessage(to: .main, text: "我上周用 Raft 做过一次选主实验"))
      _ = await settled(host)

      let reply = await Background.call(Recall("选主实验"), from: .conversation(.main), on: host)

      guard case .value(let data)? = reply else { throw HostError.invalidRequest("\(String(describing: reply))") }
      let hits = try JSONDecoder().decode([RecallHit].self, from: data)
      #expect(hits.first?.path.hasPrefix("conversations/2025-11-17/main-") == true)
      #expect(hits.first?.snippet.contains("选主实验") == true)
    }
  }

  @Test func aRunKeepsHowMuchOfItsContextItUsed() async throws {
    let agent = Background.agent { _ in .report(ContextUsage(used: 41_200, window: 400_000), reply: "看了。没变。") }
    try await withHost(agent: agent) { host, _, world in
      let entry = try await Background.add("sandbox-news", Background.draft(.hour), on: host)
      world.advance(minutes: 60)
      world.tick()

      let runs = try #require(await Background.runs(of: entry.ref, on: host, where: Background.finished))

      #expect(runs.first?.usage == ContextUsage(used: 41_200, window: 400_000))
    }
  }
}
