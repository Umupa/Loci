import Foundation
import LociModel

@testable import LociUI

/// Two mentors, one with a catalog and one just made, a few items, and one broken file.
struct Sample: Sendable {
  let scheduling: Mentor
  let sandbox: Mentor
  let borg: Item
  let items: [Item]
  let pages: [EntityID: MentorPage]
  let citedBy: [CitingLesson]
  let filterLesson: LessonRef
  var health: Health
  let text = """
    Large-scale cluster management at Google with Borg

    Google’s Borg system is a cluster manager that runs hundreds of thousands of jobs, from many thousands \
    of different applications, across a number of clusters each with up to tens of thousands of machines.

    It achieves high utilization by combining admission control, efficient task-packing, over-commitment, \
    and machine sharing with process-level performance isolation.
    """
  let lessonText = """
    调度器要回答的问题只有一个：这个任务放在哪台机器上。Borg 把它拆成两步。先做可行性检查，排除不满足约束的机器，剩下的才参与打分。

    为什么要分两步？因为约束是硬的，偏好是软的。把两者混在一个分数里，一个极高的偏好分就可能盖过一条本该否决的约束。分开之后，过滤只回答能不能，打分只回答好不好。
    """

  init(problems: Bool = true) throws {
    var entropy = Seeded()
    func id(_ offset: Double) -> EntityID {
      EntityID(at: Date(timeIntervalSince1970: 1_763_337_600 + offset), entropy: &entropy)
    }
    scheduling = try Self.mentor(id(1), "调度", 0)
    sandbox = try Self.mentor(id(2), "沙箱", 1)
    borg = try Self.item(id(3), .article, "Large-scale cluster management at Google with Borg", "en")
    items = [
      borg, try Self.item(id(4), .paper, "Firecracker: Lightweight Virtualization for Serverless", "en"),
      try Self.item(id(5), .article, "Kubernetes 调度框架：从 Filter 到 Score", "zh"),
      try Self.item(id(6), .article, "The Tail at Scale", "en"),
    ]
    filterLesson = LessonRef(mentor: scheduling.id, lesson: try Self.slug("filter-and-score"))
    let catalog = try Catalog(chapters: [
      .init(
        title: "调度要解决什么",
        lessons: [
          try Lesson(slug: try Self.slug("why-a-scheduler"), title: "为什么需要调度器"),
          try Lesson(slug: filterLesson.lesson, title: "过滤与打分"),
        ]),
      .init(
        title: "Borg 与 Kubernetes",
        lessons: [
          try Lesson(slug: try Self.slug("borg"), title: "Borg 的做法"),
          try Lesson(slug: try Self.slug("kube-scheduler"), title: "kube-scheduler 的插件框架"),
        ]),
    ])
    pages = [
      scheduling.id: MentorPage(
        mentor: scheduling, catalog: catalog,
        writtenLessons: [try Self.slug("why-a-scheduler"), filterLesson.lesson]),
      sandbox.id: MentorPage(mentor: sandbox, catalog: try Catalog(chapters: []), writtenLessons: []),
    ]
    citedBy = [
      CitingLesson(
        citation: Citation(lesson: filterLesson, item: borg.id, anchor: nil), mentorName: "调度", lessonTitle: "过滤与打分")
    ]
    health = Health(
      database: .ready, readingStateLost: false,
      fileProblems: problems
        ? [
          FileProblem(
            path: "mentors/diao-du-019a8f1c/catalog.yaml", kind: .invalid,
            reason: "chapters[1].lessons: expected Array",
            subject: .mentor(scheduling.id)),
          FileProblem(
            path: "mentors/diao-du-019a8f1c/lessons/borg.md", kind: .brokenLocator, reason: "cannot read loci://x",
            subject: .mentor(scheduling.id)),
        ] : [])
  }

  var mentors: [Mentor] { [sandbox, scheduling] }

  private static func mentor(_ id: EntityID, _ name: String, _ look: Int) throws -> Mentor {
    try Mentor(
      id: id, name: name, avatar: Mentor.portraits[look], color: MentorColor.palette[look], provider: .pi,
      permission: .full)
  }

  private static func item(_ id: EntityID, _ kind: Item.Kind, _ title: String, _ language: String) throws -> Item {
    try Item(id: id, kind: kind, title: title, language: language)
  }

  private static func slug(_ text: String) throws -> Lesson.Slug {
    guard let slug = Lesson.Slug(text) else { throw SampleError.badSlug }
    return slug
  }

  private enum SampleError: Error { case badSlug }

  private struct Seeded: RandomNumberGenerator {
    var state: UInt64 = 7
    mutating func next() -> UInt64 {
      state &+= 0x9E37_79B9_7F4A_7C15
      return state ^ (state >> 31)
    }
  }
}
