import Foundation
import LociModel
import Testing

@testable import LociHost

@Suite(.timeLimit(.minutes(1)))
struct FirstLessonScenarioTests {
  private static let catalog = """
    chapters:
    - title: Basics
      lessons:
      - slug: why-schedule
        title: Why a scheduler
      - slug: filters
        title: Filters and scores
    """

  /// Writes the catalog and the first lesson when asked to begin, and any lesson it is asked to write.
  private static let author = FakeAgent { prompt in
    if prompt.contains("new mentor") {
      return .write(
        ["catalog.yaml": catalog, "lessons/why-schedule.md": "Pods need a node.\n"], reply: "The course is ready.")
    }
    if prompt.contains("`filters`") {
      return .write(["lessons/filters.md": "First filter, then score.\n"], reply: "Written.")
    }
    return .reply("Ready.")
  }

  /// α2-S1: a sentence makes a mentor that writes its catalog and then its first lesson.
  @Test func aNewMentorWritesItsCatalogAndFirstLesson() async throws {
    try await withHost(agent: Self.author) { host, _, world in
      let mentor = try await host.run(CreateMentor(request: "想学 Kubernetes 调度"))

      let page = await value(host.subscribe(OneMentor(mentor: mentor.id))) { $0.writtenLessons.count == 1 }
      #expect(page?.catalog?.chapters.first?.lessons.map(\.slug.description) == ["why-schedule", "filters"])
      #expect(page?.writtenLessons.map(\.description) == ["why-schedule"])
      let first = try #require(await value(host.subscribe(MentorConversation(mentor: mentor.id))) { $0.turn == nil })
      guard case .prompt(let prompt) = first.messages.first?.body else {
        Issue.record("the conversation starts with Loci's prompt")
        return
      }
      #expect(prompt.purpose == .begin)
      #expect(prompt.text.contains("想学 Kubernetes 调度"))
      #expect(world.agent.opened.first?.workingDirectory.lastPathComponent.hasSuffix(mentor.id.description) == true)
    }
  }

  /// α2-S2: while the mentor works, the conversation says what it is doing.
  @Test func theMentorsWorkIsVisibleBeforeTheCatalogExists() async throws {
    try await withHost(agent: FakeAgent { _ in .hang }) { host, _, _ in
      let mentor = try await host.run(CreateMentor(request: "Scheduling"))

      let working = await value(host.subscribe(MentorConversation(mentor: mentor.id))) { $0.turn != nil }
      #expect(working?.turn?.messages.count ?? 0 >= 1)
      _ = try await host.run(StopTurn(mentor: mentor.id))
    }
  }

  /// α2-S3: a lesson in the catalog that is not written yet can be asked for.
  @Test func anUnwrittenLessonCanBeRequested() async throws {
    try await withHost(agent: Self.author) { host, _, world in
      let mentor = try await host.run(CreateMentor(request: "Scheduling"))
      let pages = host.subscribe(OneMentor(mentor: mentor.id))
      _ = await value(pages) { $0.writtenLessons.count == 1 }
      _ = await value(host.subscribe(MentorConversation(mentor: mentor.id))) { $0.turn == nil }

      _ = try await host.run(WriteLesson(lesson: LessonRef(mentor: mentor.id, lesson: Lesson.Slug("filters")!)))

      let written = await value(pages) { $0.writtenLessons.count == 2 }
      #expect(written != nil)
      #expect(world.agent.prompts.last?.contains("lessons/filters.md") == true)
    }
  }

  @Test(arguments: ["why-schedule", "missing"])
  func aWrittenOrUnlistedLessonCannotBeRequested(slug: String) async throws {
    try await withHost(agent: Self.author) { host, _, _ in
      let mentor = try await host.run(CreateMentor(request: "Scheduling"))
      _ = await value(host.subscribe(OneMentor(mentor: mentor.id))) { $0.writtenLessons.count == 1 }
      _ = await value(host.subscribe(MentorConversation(mentor: mentor.id))) { $0.turn == nil }

      await #expect(throws: HostError.self) {
        try await host.run(WriteLesson(lesson: LessonRef(mentor: mentor.id, lesson: Lesson.Slug(slug)!)))
      }
    }
  }
}
