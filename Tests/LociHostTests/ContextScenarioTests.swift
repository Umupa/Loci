import Foundation
import LociModel
import LociStore
import Testing

@testable import LociHost

/// L-S5: each message Loci gets starts with what changed around it, and only what changed.
@Suite(.timeLimit(.minutes(1)))
struct ContextScenarioTests {
  private func say(_ text: String, to host: LocalHost, prompts: Int) async throws {
    _ = try await host.run(SendMessage(to: .main, text: text))
    _ = try #require(await settled(host, prompts: prompts))
  }

  @Test func everyMessageSaysWhenItIs() async throws {
    try await withHost { host, _, world in
      try await say("早", to: host, prompts: 1)
      world.set(to: "23:40")
      try await say("还没睡", to: host, prompts: 2)

      #expect(world.agent.prompts.first?.contains("Now: Monday 2025-11-17 08:00, morning (Asia/Shanghai)") == true)
      #expect(world.agent.prompts.last?.contains("Now: Monday 2025-11-17 23:40, late night (Asia/Shanghai)") == true)
    }
  }

  @Test func memoryAndNotesAreShownOnceAndAgainOnlyWhenTheyChange() async throws {
    try await withHost { host, place, world in
      let memory = place.root.appending(path: "agent/MEMORY.md")
      try place.store.setMemoryWritable(true)
      try place.edit(memory) { $0 + "- 2025-11-02 先给结论\n" }

      try await say("one", to: host, prompts: 1)
      try await say("two", to: host, prompts: 2)
      try place.edit(memory) { $0 + "- 2025-11-17 不要出题考\n" }
      try await say("three", to: host, prompts: 3)

      let prompts = world.agent.prompts
      #expect(prompts[0].contains("MEMORY.md:\n# Memory\n- 2025-11-02 先给结论"))
      #expect(prompts[0].contains("notes/2025-11-17.md:\n(empty)"))
      #expect(!prompts[1].contains("MEMORY.md:"))
      #expect(!prompts[1].contains("notes/2025-11-17.md:"))
      #expect(prompts[2].contains("不要出题考"))
      #expect(!prompts[2].contains("notes/2025-11-16.md:"))
    }
  }

  @Test func whatWasShownIsRememberedAcrossARestart() async throws {
    let place = Place()
    defer { place.remove() }
    let world = TestWorld()
    let first = try await LocalHost.start(root: place.root, database: place.database, environment: world.environment)
    try await say("one", to: first, prompts: 1)
    await first.close()

    let second = try await LocalHost.start(root: place.root, database: place.database, environment: world.environment)
    try await say("two", to: second, prompts: 2)
    await second.close()

    #expect(world.agent.opened.last?.resume != nil)
    #expect(world.agent.prompts.last?.contains("MEMORY.md:") == false)
  }

  @Test func longNotesAreCutToTheirLatestPart() async throws {
    try await withHost { host, place, world in
      let notes = (0..<2_000).map { "- 08:00 [main] note \($0) " + String(repeating: "x", count: 20) }
      try place.store.writeNotes("# 2025-11-17\n" + notes.joined(separator: "\n") + "\n", on: "2025-11-17")

      try await say("one", to: host, prompts: 1)

      let prompt = try #require(world.agent.prompts.first)
      #expect(prompt.contains("note 1999"))
      #expect(!prompt.contains("note 0 "))
      #expect(prompt.contains("the daily review moves what is worth keeping into memory/"))
    }
  }

  @Test func whatHappenedSinceLastTimeIsToldOnceAsFacts() async throws {
    try await withHost { host, _, world in
      try await say("one", to: host, prompts: 1)
      world.advance(minutes: 5)
      let item = try await host.run(AddTextItem(fileName: "raft.md", text: "# Raft\n\nterm and index\n"))
      _ = try await host.run(MarkRead(content: .item(item.id)))
      world.advance(minutes: 5)

      try await say("two", to: host, prompts: 2)
      try await say("three", to: host, prompts: 3)

      let prompts = world.agent.prompts
      #expect(prompts[1].contains("Since we last talked here:"))
      #expect(prompts[1].contains("- 08:05 saved an article \"Raft\" (library/\(item.id)) to the library"))
      #expect(prompts[1].contains("- 08:05 finished reading \"Raft\" (library/\(item.id))"))
      #expect(!prompts[2].contains("Since we last talked here:"))
    }
  }

  @Test func theMainConversationKnowsWhatWasJustBeingRead() async throws {
    try await withHost { host, _, world in
      let item = try await host.run(AddTextItem(fileName: "raft.md", text: "# Raft\n\nterm and index\n"))
      _ = try await host.run(
        SaveReadingPosition(content: .item(item.id), position: .item(item.id, .quote(try TextQuote("term")))))

      try await say("one", to: host, prompts: 1)

      #expect(world.agent.prompts.first?.contains("Open: the person was just reading \"Raft\"") == true)
    }
  }
}

extension Store {
  func writeNotes(_ text: String, on day: String) throws {
    try Data(text.utf8).write(to: dayNotesFile(of: Day(day) ?? Day(containing: Timestamp(.now), in: .gmt)))
  }
}
