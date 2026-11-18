import Foundation
import GRDB
import LociModel

@testable import LociStore

extension StoreDatabase {
  /// Every mirror row as text, sorted, so two databases can be compared table by table. Search owners
  /// are compared by the row they own, since row numbers depend on the order rows were written.
  func mirrors() throws -> [String: [String]] {
    try queue.read { db in
      var tables: [String: [String]] = [:]
      for table in Schema.mirrorTables where table != "search_owner" {
        tables[table] = try Row.fetchAll(db, sql: "SELECT * FROM \(table)").map(\.description).sorted()
      }
      tables["search_owner"] = try Row.fetchAll(
        db,
        sql: """
          SELECT o.owner, s.target, s.field FROM search_owner o JOIN search s ON s.rowid = o.search_rowid
          """
      ).map(\.description).sorted()
      return tables
    }
  }
}

/// A folder with an article and a video, and a note on the article.
struct Library {
  let store: Store
  let article: Item
  let video: Item
  let note: Note

  init(store: Store) throws {
    self.store = store
    article = try Fixture.item(3)
    video = try Item(id: Fixture.id(4), kind: .video(duration: .seconds(600)), title: "Borg, Omega, and Kubernetes")
    note = try Note(
      id: Fixture.id(10), locator: .item(article.id, .quote(try TextQuote("feasibility checking"))),
      excerpt: "feasibility checking", thought: "像漏斗一样先筛一遍",
      exchanges: [try Note.Exchange(question: "为什么先过滤?", answer: "打分很贵，先把不可能的机器去掉。", askedAt: Fixture.instant)],
      savedAt: Fixture.instant)

    try store.add(
      article,
      content: "Borg uses feasibility checking to find machines on which a task could run, then scoring.\n"
        + "调度器的基本问题是把任务放到合适的机器上。\n")
    try store.add(video, content: "")
    try store.append(.saved(note), on: .item(article.id))
  }
}
