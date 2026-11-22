import Foundation
import LociModel
import Testing

@testable import LociStore

struct AgentFilesTests {
  @Test func preparingGivesLociItsFilesAndLeavesTheOnesThereAlone() throws {
    try withStore { store in
      try store.writeFile("agent/USER.md", "# User\n- 叫我小王\n")

      try store.prepareAgent(soul: "You are Loci.\n\n## Evolved Traits\n")
      try store.prepareAgent(soul: "something else")

      #expect(try store.agentText(.soul) == "You are Loci.\n\n## Evolved Traits\n")
      #expect(try store.agentText(.profile) == "# User\n- 叫我小王\n")
      #expect(try store.agentText(.memory) == "# Memory\n")
      for folder in ["notes", "diary", "workspace", "conversations"] {
        #expect(FileManager.default.fileExists(atPath: store.agentFolder.appending(path: folder).path()))
      }
    }
  }

  @Test func openingAnOlderLibraryRemovesTheStockNameAndKeepsEvolvedTraitsAndCustomSouls() throws {
    try withStore { store in
      let core = "# Soul\n\nYou live on this Mac, among the person's library and courses."
      let traits = "\n\n## Evolved Traits\n- 2026-11-18 Curious about watches.\n"
      let old = core.replacing("You live", with: "You are Loci. You live") + traits
      try store.writeFile("agent/SOUL.md", old)
      try store.prepareAgent(soul: core + "\n\n## Evolved Traits\n")
      #expect(try store.agentText(.soul) == core + traits)
      try store.saveAgentText("My own words." + traits, as: .soul)
      try store.prepareAgent(soul: core + "\n\n## Evolved Traits\n")
      #expect(try store.agentText(.soul) == "My own words." + traits)
    }
  }

  @Test func anUnreadableSoulDoesNotKeepTheLibraryFromOpening() throws {
    try withStore { store in
      let soul = store.agentFolder.appending(path: "SOUL.md")
      let original = Data([0xff, 0xfe, 0xfa])
      try store.write(original, to: soul)
      try store.prepareAgent(soul: "# Soul")
      #expect(try Data(contentsOf: soul) == original)
    }
  }

  @Test func aMissingFileReadsAsEmpty() throws {
    try withStore { store in
      let day = try #require(Day("2026-11-18"))
      #expect(try store.agentText(.memory) == "")
      #expect(try store.dayNotes(of: day) == "")
      #expect(throws: StoreError.self) { try store.diary(of: day) }
    }
  }

  @Test func diariesAreListedNewestFirst() throws {
    try withStore { store in
      try store.writeFile("agent/diary/2026-11-16.md", "a")
      try store.writeFile("agent/diary/2026-11-17.md", "b")
      try store.writeFile("agent/diary/notes.md", "not a day")

      #expect(store.diaryDays() == [Day("2026-11-17"), Day("2026-11-16")])
      #expect(try store.diary(of: try #require(Day("2026-11-17"))) == "b")
    }
  }

  @Test func theInstructionsAreWrittenAndClaudeCodeIsPointedAtThem() throws {
    try withStore { store in
      try store.writeInstructions("rules")
      try store.writeInstructions("new rules")

      #expect(try store.readFile("agent/AGENTS.md") == "new rules")
      #expect(try store.readFile("agent/CLAUDE.md") == "new rules")
    }
  }

  @Test func aClaudeFileOfThePersonsOwnIsKept() throws {
    try withStore { store in
      try store.writeFile("agent/CLAUDE.md", "mine")

      try store.writeInstructions("rules")

      #expect(try store.readFile("agent/CLAUDE.md") == "mine")
    }
  }

  @Test func anAvatarReplacesTheOneBeforeAndCanBeTakenAway() throws {
    try withStore { store in
      #expect(try store.avatar() == nil)

      try store.setAvatar(try Avatar(data: Data([1]), format: "png"))
      try store.setAvatar(try Avatar(data: Data([2]), format: "jpg"))

      let chosen = try Avatar(data: Data([2]), format: "jpg")
      #expect(try store.avatar() == chosen)
      #expect(!FileManager.default.fileExists(atPath: store.agentFolder.appending(path: "avatar.png").path()))
      try store.resetAvatar()
      #expect(try store.avatar() == nil)
    }
  }

  @Test func aConversationIsCopiedByDayAndBySession() throws {
    try withStore { store in
      let shanghai = try #require(TimeZone(identifier: "Asia/Shanghai"))
      let session = SessionTests.session(10, .conversation(.item(Fixture.id(2))))
      let lateNight = try #require(Timestamp("2026-11-17T15:58:00.000Z"))
      let pastMidnight = try #require(Timestamp("2026-11-17T16:02:00.000Z"))
      let tool = ToolActivity(id: "t", name: "bash", kind: .execute, subject: "ls", output: "", state: .succeeded)
      try store.mirror(
        [
          Message(id: Fixture.id(20), at: lateNight, body: .prompt(Prompt(text: "为什么?", purpose: .chat))),
          Message(id: Fixture.id(21), at: lateNight, body: .thinking("hmm")),
          Message(id: Fixture.id(22), at: pastMidnight, body: .tool(tool)),
          Message(id: Fixture.id(23), at: pastMidnight, body: .reply("因为 fd 属于进程。")),
        ], of: session, in: shanghai)
      try store.mirror(
        [Message(id: Fixture.id(24), at: pastMidnight, body: .prompt(Prompt(text: "懂了", purpose: .chat)))],
        of: session, in: shanghai)

      let name = "library-\(Fixture.id(2))-\(Fixture.id(10)).md"
      #expect(
        try store.readFile("agent/conversations/2026-11-17/\(name)")
          == "# library-\(Fixture.id(2)) · 2026-11-17\n\n### 23:58 · You\n\n为什么?\n")
      #expect(
        try store.readFile("agent/conversations/2026-11-18/\(name)")
          == "# library-\(Fixture.id(2)) · 2026-11-18\n\n### 00:02 · Companion\n\n- execute: ls\n因为 fd 属于进程。\n"
          + "\n### 00:02 · You\n\n懂了\n")
    }
  }
}
