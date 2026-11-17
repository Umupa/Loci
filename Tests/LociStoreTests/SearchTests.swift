import Foundation
import LociModel
import Testing

@testable import LociStore

struct SearchTests {
  static func searching(_ body: (StoreDatabase, Library) throws -> Void) throws {
    try withStore { store in
      let library = try Library(store: store)
      let database = try StoreDatabase.inMemory()
      try database.rebuild(from: store)
      try body(database, library)
    }
  }

  @Test func aChineseWordFindsTheLongerWordsThatContainIt() throws {
    try Self.searching { database, library in
      let hits = try database.search("调度")

      #expect(hits.contains { $0.target == .mentor(library.first.id) && $0.field == .name })
      #expect(hits.contains { $0.target == .item(library.article.id) && $0.field == .body })
      #expect(hits.contains { $0.target == .lesson(library.firstLesson) && $0.field == .title } == false)
    }
  }

  @Test func eachKindOfTextCanBeFound() throws {
    try Self.searching { database, library in
      let titles = try database.search("打分")
      let note = try database.search("漏斗")

      #expect(try database.search("Distributed").map(\.target) == [.mentor(library.second.id)])
      #expect(titles.contains { $0.target == .lesson(library.firstLesson) && $0.field == .title })
      #expect(try database.search("Omega").map(\.field) == [.title])
      #expect(
        note == [
          SearchHit(
            target: .note(library.note.id, on: .item(library.article.id)), field: .note,
            snippet: "feasibility checking 像漏斗一样先筛一遍 为什么先过滤? 打分很贵，先把不可能的机器去掉。",
            locator: library.note.locator)
        ])
      #expect(try database.search("不可能的机器").map(\.field) == [.note])
    }
  }

  @Test func aSingleCharacterAndALatinPrefixBothMatch() throws {
    try Self.searching { database, library in
      let prefix = try database.search("feasib")

      #expect(try database.search("筛").map(\.target) == [.note(library.note.id, on: .item(library.article.id))])
      #expect(prefix.contains { $0.target == .item(library.article.id) })
      #expect(try database.search("KUBERNETES").map(\.target) == [.item(library.video.id)])
    }
  }

  @Test func everyWordMustMatch() throws {
    try Self.searching { database, library in
      let both = try database.search("Borg 调度")
      let missing = try database.search("Borg 不存在")

      #expect(both.map(\.target) == [.item(library.article.id)])
      #expect(missing.isEmpty)
    }
  }

  @Test func aMatchInAnItemsTextPointsAtTheSentence() throws {
    try Self.searching { database, library in
      let hit = try #require(try database.search("合适的机器").first)

      #expect(hit.snippet == "… could run, then scoring. 调度器的基本问题是把任务放到合适的机器上。")
      guard case .item(let item, .quote(let quote)) = hit.locator else {
        Issue.record("expected a quote locator, got \(String(describing: hit.locator))")
        return
      }
      #expect(item == library.article.id)
      #expect(quote.text == "合适的机器")
      #expect(quote.before == "un, then scoring.\n调度器的基本问题是把任务放到")
      #expect(Locator(hit.locator!.description) == hit.locator)
    }
  }

  @Test(arguments: ["", "   ", "\"", "*", "OR", "AND NOT", "(调度", "NEAR(a b)", "a:b", "^", "-x"])
  func queryCharactersAreSearchedForNotObeyed(text: String) throws {
    try Self.searching { database, _ in
      _ = try database.search(text)
    }
  }

  @Test func titlesRankAboveText() throws {
    try Self.searching { database, library in
      let hits = try database.search("Borg")

      #expect(hits.first?.field == .title)
      #expect(hits.contains { $0.target == .item(library.article.id) && $0.field == .body })
    }
  }
}
