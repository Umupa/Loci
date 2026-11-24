import Foundation
import LociModel
import Testing

@testable import LociStore

/// ME-S2, ME-S3: the wiki's pages, read-only outside the review, and what changed since the review last ended.
struct MemoryFilesTests {
  private func agent(_ store: Store, _ path: String) -> URL { store.agentFolder.appending(path: path) }

  @Test func theIndexAndTheWikiCannotBeWrittenInPlaceOutsideTheReview() throws {
    try withStore { store in
      try store.prepareAgent(soul: "# Soul\n")
      try store.setMemoryWritable(true)
      try Data("# Raft\n".utf8).write(to: agent(store, "memory/raft.md"))

      try store.setMemoryWritable(false)

      #expect(!store.memoryIsWritable)
      #expect(throws: (any Error).self) { try Data("x".utf8).write(to: agent(store, "memory/raft.md")) }
      #expect(throws: (any Error).self) { try Data("x".utf8).write(to: agent(store, "memory/new.md")) }
      try store.setMemoryWritable(true)
      try Data("# Raft\n- more\n".utf8).write(to: agent(store, "memory/raft.md"))
      #expect(try store.wikiPage("raft") == "# Raft\n- more\n")
      #expect(store.wikiPages() == ["raft"])
    }
  }

  @Test func whatChangedSinceTheReviewLastEndedIsFoundAddedRemovedAndEdited() throws {
    try withStore { store in
      try store.prepareAgent(soul: "# Soul\n")
      try store.setMemoryWritable(true)
      try Data("# A\n".utf8).write(to: agent(store, "memory/a.md"))
      try Data("# B\n".utf8).write(to: agent(store, "memory/b.md"))
      #expect(store.memoryChangedSinceKept().isEmpty)
      try store.keepMemory()

      try Data("# A, changed\n".utf8).write(to: agent(store, "memory/a.md"))
      try FileManager.default.removeItem(at: agent(store, "memory/b.md"))
      try Data("# C\n".utf8).write(to: agent(store, "memory/c.md"))

      #expect(store.memoryChangedSinceKept() == ["memory/a.md", "memory/b.md", "memory/c.md"])
    }
  }

  @Test func theAppsOwnChangeToTheIndexKeepsItReadOnlyAndIsNotTakenForAnotherOne() throws {
    try withStore { store in
      try store.prepareAgent(soul: "# Soul\n")
      try store.setMemoryWritable(false)
      try store.keepMemory()

      try store.saveAgentText("# Memory\n- 2026-11-02 先给结论\n", as: .memory)

      #expect(try store.agentText(.memory).contains("先给结论"))
      #expect(!store.memoryIsWritable)
      #expect(store.memoryChangedSinceKept().isEmpty)
    }
  }
}

/// ME-S5: every word said in a conversation or a run can be found again, with the file it is in.
struct TranscriptSearchTests {
  @Test func wordsSaidInAConversationOrARunAreFoundWithTheirFile() throws {
    try withStore { store in
      let database = try StoreDatabase.inMemory()
      let run = Store.runRecordPath(of: Fixture.id(10), on: try #require(Day("2026-11-20")))
      try store.saveRunRecord("# run\n\n## Found\n\nCubeSandbox 发了 v0.9.0，快照恢复快了三倍。\n", at: run)
      try database.indexTranscript(run, from: store)

      let hits = try database.recall("快照恢复")

      #expect(hits.map(\.path) == [run])
      #expect(hits.first?.day == Day("2026-11-20"))
      #expect(hits.first?.snippet.contains("快照恢复快了三倍") == true)
      #expect(try database.recall("Kubernetes").isEmpty)
    }
  }

  @Test func theTranscriptsAreReadAgainWhenTheIndexIsRebuiltFromTheFiles() throws {
    try withStore { store in
      let database = try StoreDatabase.inMemory()
      let run = Store.runRecordPath(of: Fixture.id(11), on: try #require(Day("2026-11-21")))
      try store.saveRunRecord("# run\n\n周五再看 #412 有没有人回。\n", at: run)

      try database.rebuild(from: store)

      #expect(try database.recall("412").map(\.path) == [run])
      #expect(store.transcriptPaths() == [run])
    }
  }
}
