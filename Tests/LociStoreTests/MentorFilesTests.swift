import Foundation
import LociModel
import Synchronization
import Testing

@testable import LociStore

struct MentorFilesTests {
  @Test func aCreatedMentorReadsBackWithAnEmptyCatalog() throws {
    try withStore { store in
      let mentor = try Fixture.mentor()
      try store.create(mentor)

      #expect(try store.mentor(mentor.id) == mentor)
      #expect(try store.catalog(of: mentor.id).chapters.isEmpty)
    }
  }

  @Test func mentorJSONIsSortedIndentedAndKeepsChineseReadable() throws {
    try withStore { store in
      let mentor = try Fixture.mentor()
      try store.create(mentor)
      let folder = try store.folderName(ofMentor: mentor.id)

      #expect(
        try store.readFile("mentors/\(folder)/mentor.json") == """
          {
            "avatar" : "owl",
            "color" : "#b5523b",
            "id" : "\(mentor.id)",
            "name" : "调度",
            "permission" : "full",
            "provider" : "claude-code"
          }

          """)
    }
  }

  @Test func theFolderIsNamedForPeopleAndTheIDInside() throws {
    try withStore { store in
      try store.create(try Fixture.mentor(1, name: "调度"))
      try store.create(try Fixture.mentor(2, name: "Kubernetes: the Scheduler, Explained!"))
      try store.create(try Fixture.mentor(3, name: "🦉"))

      #expect(try store.folderName(ofMentor: Fixture.id(1)) == "diao-du-\(Fixture.id(1))")
      #expect(try store.folderName(ofMentor: Fixture.id(2)) == "kubernetes-the-scheduler-explained-\(Fixture.id(2))")
      #expect(try store.folderName(ofMentor: Fixture.id(3)) == Fixture.id(3).description)
    }
  }

  @Test func longNamesAreCutAtAWord() {
    let name = FolderName.shortName(String(repeating: "scheduling ", count: 10))

    #expect(name.count <= FolderName.longestShortName)
    #expect(!name.hasSuffix("-"))
    #expect(name.hasPrefix("scheduling-scheduling"))
  }

  @Test func aRenamedFolderIsStillFoundByTheIDInside() throws {
    try withStore { store in
      let mentor = try Fixture.mentor()
      try store.create(mentor)
      let folder = store.root.appending(path: "mentors/\(try store.folderName(ofMentor: mentor.id))")
      try FileManager.default.moveItem(at: folder, to: store.root.appending(path: "mentors/my scheduling notes"))

      #expect(try store.mentor(mentor.id) == mentor)
    }
  }

  @Test func savingAMentorKeepsItsFolderName() throws {
    try withStore { store in
      let mentor = try Fixture.mentor()
      try store.create(mentor)
      let renamed = try Mentor(
        id: mentor.id, name: "Scheduling", avatar: "owl", color: mentor.color, provider: .pi, permission: .ask)
      try store.save(renamed)

      #expect(try store.mentor(mentor.id) == renamed)
      #expect(try store.folderName(ofMentor: mentor.id) == "diao-du-\(mentor.id)")
    }
  }

  @Test func creatingTheSameMentorTwiceIsRefused() throws {
    try withStore { store in
      let mentor = try Fixture.mentor()
      try store.create(mentor)

      #expect(throws: StoreError.alreadyExists(mentor.id)) { try store.create(mentor) }
    }
  }

  @Test func catalogAndLessonsSurviveTheirFiles() throws {
    try withStore { store in
      let mentor = try Fixture.mentor()
      try store.create(mentor)
      let catalog = try Catalog(chapters: [
        .init(title: "调度的基本问题", lessons: [try Lesson(slug: Fixture.slug("filter-and-score"), title: "过滤与打分")]),
        .init(title: "还没开始的一章", lessons: []),
      ])
      let ref = LessonRef(mentor: mentor.id, lesson: Fixture.slug("filter-and-score"))
      let lesson = LessonText(
        front: try Lesson.Front(sources: [.item(Fixture.id(2))]), body: "# 过滤与打分\n\nBorg 先排除不满足约束的机器。\n")
      try store.save(catalog, of: mentor.id)
      try store.save(lesson, as: ref)
      let folder = try store.folderName(ofMentor: mentor.id)

      #expect(try store.catalog(of: mentor.id) == catalog)
      #expect(try store.lesson(ref) == lesson)
      #expect(try store.readFile("mentors/\(folder)/catalog.yaml").contains("title: 调度的基本问题"))
      #expect(
        try store.readFile("mentors/\(folder)/lessons/filter-and-score.md")
          == "---\nsources:\n- \(Fixture.id(2))\n---\n# 过滤与打分\n\nBorg 先排除不满足约束的机器。\n")
    }
  }

  @Test func aLessonNotWrittenYetIsNotFound() throws {
    try withStore { store in
      let mentor = try Fixture.mentor()
      try store.create(mentor)

      #expect(throws: StoreError.self) { try store.lesson(LessonRef(mentor: mentor.id, lesson: Fixture.slug("later"))) }
    }
  }

  @Test func anInvalidFileSaysWhichFileAndWhy() throws {
    try withStore { store in
      let mentor = try Fixture.mentor()
      try store.create(mentor)
      let folder = try store.folderName(ofMentor: mentor.id)
      try store.writeFile(
        "mentors/\(folder)/mentor.json",
        try store.readFile("mentors/\(folder)/mentor.json").replacing("claude-code", with: "claude"))

      #expect {
        try store.mentor(mentor.id)
      } throws: { error in
        guard case StoreError.invalid(let problem) = error else { return false }
        return problem.path == "mentors/\(folder)/mentor.json" && problem.kind == .invalid
          && problem.reason.contains("provider")
      }
    }
  }

  @Test func deletingAMentorGoesThroughTheDiscardItWasGiven() throws {
    let discarded = Mutex<[String]>([])
    let root = temporaryStore().root
    defer { try? FileManager.default.removeItem(at: root) }
    let store = Store(root: root, discard: Discard { url in discarded.withLock { $0.append(url.lastPathComponent) } })
    let mentor = try Fixture.mentor()
    try store.create(mentor)
    let folder = try store.folderName(ofMentor: mentor.id)
    try store.append(
      .deleted(Fixture.id(9), at: Fixture.instant),
      on: .lesson(LessonRef(mentor: mentor.id, lesson: Fixture.slug("intro"))))

    try store.deleteMentor(mentor.id, notes: .delete)

    #expect(discarded.withLock { $0 } == [folder, mentor.id.description])
  }

  @Test func aDeletedMentorIsGone() throws {
    try withStore { store in
      let mentor = try Fixture.mentor()
      try store.create(mentor)
      try store.deleteMentor(mentor.id, notes: .keep)

      #expect(throws: StoreError.notFound(mentor.id.description)) { try store.mentor(mentor.id) }
    }
  }
}
