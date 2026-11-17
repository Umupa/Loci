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

/// A folder with two mentors that both cite one article, and a note on that article.
struct Library {
  let store: Store
  let first: Mentor
  let second: Mentor
  let article: Item
  let video: Item
  let firstLesson: LessonRef
  let secondLesson: LessonRef
  let note: Note

  init(store: Store) throws {
    self.store = store
    first = try Fixture.mentor(1, name: "调度")
    second = try Fixture.mentor(2, name: "Distributed Systems")
    article = try Fixture.item(3)
    video = try Item(id: Fixture.id(4), kind: .video(duration: .seconds(600)), title: "Borg, Omega, and Kubernetes")
    firstLesson = LessonRef(mentor: first.id, lesson: Fixture.slug("filter-and-score"))
    secondLesson = LessonRef(mentor: second.id, lesson: Fixture.slug("cluster-managers"))
    note = try Note(
      id: Fixture.id(10), locator: .item(article.id, .quote(try TextQuote("feasibility checking"))),
      excerpt: "feasibility checking", thought: "像漏斗一样先筛一遍",
      exchanges: [
        try Note.Exchange(
          question: "为什么先过滤?", answer: "打分很贵，先把不可能的机器去掉。", mentor: first.id, askedAt: Fixture.instant)
      ], savedAt: Fixture.instant)

    try store.create(first)
    try store.create(second)
    try store.add(
      article,
      content: "Borg uses feasibility checking to find machines on which a task could run, then scoring.\n"
        + "调度器的基本问题是把任务放到合适的机器上。\n")
    try store.add(video, content: "")
    try store.save(
      try Catalog(chapters: [
        .init(title: "调度的基本问题", lessons: [try Lesson(slug: firstLesson.lesson, title: "过滤与打分")])
      ]), of: first.id)
    try store.save(
      LessonText(
        front: try Lesson.Front(sources: [.item(article.id)]),
        body: "先过滤（[原文](loci://library/\(article.id)#quote=feasibility%20checking)），再打分。\n"
          + "演讲 <loci://library/\(video.id)#t=60,90>。\n"),
      as: firstLesson)
    try store.save(
      try Catalog(chapters: [
        .init(title: "Cluster managers", lessons: [try Lesson(slug: secondLesson.lesson, title: "Borg")])
      ]),
      of: second.id)
    try store.save(LessonText(front: try Lesson.Front(sources: [.item(article.id)]), body: "Borg.\n"), as: secondLesson)
    try store.append(.saved(note), on: .item(article.id))
  }
}
