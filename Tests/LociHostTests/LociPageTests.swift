import Foundation
import LociModel
import LociStore
import Testing

@testable import LociHost

/// L-S8: the Loci page shows what Loci is and remembers, from the files, and follows them as they change.
@Suite(.timeLimit(.minutes(1)))
struct LociPageTests {
  @Test func aNewLociHasItsDefaultSoulAndNothingRemembered() async throws {
    try await withHost { host, _, _ in
      let page = try await host.lociPage()

      #expect(page.soul.core.hasPrefix("# Soul\n\nYou are Loci."))
      #expect(page.soul.traits.isEmpty)
      #expect(page.memory.isEmpty && page.profile.isEmpty && page.today.notes.isEmpty && page.diaries.isEmpty)
      #expect(page.together == Together(days: 0, messages: 0, itemsReadTogether: 0))
    }
  }

  @Test func thePageShowsWhatTheFilesSay() async throws {
    try await withHost { host, place, _ in
      let item = try await host.run(AddTextItem(fileName: "raft.md", text: "# Raft\n\nterm\n"))
      let agent = place.root.appending(path: "agent")
      try place.edit(agent.appending(path: "MEMORY.md")) {
        $0 + "- 2025-11-12 混淆过 term 和 index loci://library/\(item.id)#quote=term\nloose words\n"
      }
      try place.edit(agent.appending(path: "USER.md")) { $0 + "- 2025-11-01 中文，叫「你」就好\n" }
      try place.edit(agent.appending(path: "SOUL.md")) { $0 + "- 2025-11-09 发现自己喜欢画图\n" }
      try place.store.writeNotes("# 2025-11-17\n- 00:31 [library/\(item.id)] 读完\n", on: "2025-11-17")

      let page = try await host.lociPage()

      guard case .entry(let memory) = page.memory.first else { throw HostError.notFound("memory") }
      #expect(memory.text == "混淆过 term 和 index")
      #expect(memory.source?.itemTitle == "Raft")
      #expect(page.memory.last == .text("loose words"))
      #expect(page.profile.count == 1)
      #expect(page.soul.traits == [.entry(Trait(day: Day("2025-11-09"), text: "发现自己喜欢画图"))])
      #expect(
        page.today.notes == [
          .entry(DayNote(time: TimeOfDay("00:31"), text: "读完", from: .item(item.id, title: "Raft")))
        ])
      #expect(await host.localFile(.agentFolder)?.url.standardizedFileURL == agent.standardizedFileURL)
    }
  }

  @Test func thePageFollowsTheFilesAsTheyChange() async throws {
    try await withHost { host, place, _ in
      let feed = host.subscribe(LociHome())
      _ = await value(feed) { _ in true }

      try place.edit(place.root.appending(path: "agent/MEMORY.md")) { $0 + "- 不要出题考\n" }

      #expect(await value(feed) { $0.memory.count == 1 } != nil)
    }
  }

  @Test func forgettingTakesOutOneEntryAndLeavesTheRest() async throws {
    try await withHost { host, place, _ in
      let memory = place.root.appending(path: "agent/MEMORY.md")
      try place.edit(memory) { $0 + "- a\n  more of a\n- b\n" }

      _ = try await host.run(Forget("- a", in: .memory))

      #expect(try String(contentsOf: memory, encoding: .utf8) == "# Memory\n- b\n")
      await #expect(throws: HostError.notFound("- a")) { try await host.run(Forget("- a", in: .memory)) }
    }
  }

  @Test func savingTheSoulKeepsTheTraits() async throws {
    try await withHost { host, place, _ in
      try place.edit(place.root.appending(path: "agent/SOUL.md")) { $0 + "- 2025-11-09 爱画图\n" }

      let soul = try await host.run(SaveSoul(core: "You are Loci, briefly."))

      #expect(soul.core == "You are Loci, briefly.")
      #expect(soul.traits == [.entry(Trait(day: Day("2025-11-09"), text: "爱画图"))])
      await #expect(throws: HostError.self) { try await host.run(SaveSoul(core: "  ")) }
    }
  }

  @Test func theDaysAndWhatWasSaidAreCounted() async throws {
    try await withHost { host, _, world in
      let item = try await host.run(AddTextItem(fileName: "raft.md", text: "# Raft\n\nterm\n"))
      _ = try await host.run(SendMessage(to: .main, text: "Hi"))
      _ = try #require(await settled(host))
      world.set(to: "10:00", daysLater: 2)
      _ = try await host.run(SendMessage(to: .item(item.id), text: "Why?"))
      _ = try #require(await settled(host, .item(item.id)))

      #expect(try await host.lociPage().together == Together(days: 3, messages: 2, itemsReadTogether: 1))
    }
  }

  @Test func aDiaryIsReadWholeAndListedByItsHeading() async throws {
    try await withHost { host, place, _ in
      try place.store.writeDiary(
        "# 2025-11-16 23:48 — 三个没被点开的视频\n\n有点失落。\n\n## To remember\n- 最多推荐三个\n", on: "2025-11-16")

      let page = try await host.lociPage()
      let diary = try await host.diary(of: try #require(Day("2025-11-16")))

      #expect(page.diaries.map(\.title) == ["三个没被点开的视频"])
      #expect(diary.body == "有点失落。")
      #expect(diary.toRemember == ["最多推荐三个"])
      await #expect(throws: HostError.self) { try await host.diary(of: try #require(Day("2025-11-15"))) }
    }
  }

  @Test func anAvatarIsSharedEverywhereAndCanBeTakenBack() async throws {
    try await withHost { host, _, _ in
      let feed = host.subscribe(LociAvatar())
      let picture = try Avatar(data: Data([1, 2, 3]), format: "png")

      _ = try await host.run(SetAvatar(picture))
      #expect(await value(feed) { $0 != nil } == picture)

      _ = try await host.run(ResetAvatar())
      #expect(await value(feed) { $0 == nil } != nil)
    }
  }
}

extension Store {
  func writeDiary(_ text: String, on day: String) throws {
    try Data(text.utf8).write(to: diaryFile(of: Day(day) ?? Day(containing: Timestamp(.now), in: .gmt)))
  }
}
